import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:map_launcher/map_launcher.dart' hide MapType;
import 'package:flutter_svg/flutter_svg.dart';

// ============================================================================
// GLOBAL HELPERS & MODELS
// ============================================================================

final ValueNotifier<ThemeMode> themeNotifier = ValueNotifier(ThemeMode.system);

class MyHttpOverrides extends HttpOverrides {
  @override
  HttpClient createHttpClient(SecurityContext? context) {
    return super.createHttpClient(context)..badCertificateCallback = (X509Certificate cert, String host, int port) => true;
  }
}

void main() {
  HttpOverrides.global = MyHttpOverrides();
  runApp(const BlackPinApp());
}

enum CafeState { open, closingSoon, opensSoon, closed, unknown }
enum PetStatus { friendly, conditional, none }

class CafeStatus {
  final CafeState state;
  final String displayMessage;
  const CafeStatus(this.state, this.displayMessage);
  bool get isOpen { return state == CafeState.open || state == CafeState.closingSoon || state == CafeState.opensSoon; }
}

PetStatus parsePetStatus(String val) {
  val = val.toUpperCase().trim();
  if (val == 'Y' || val == 'YES' || val == 'FRIENDLY') { return PetStatus.friendly; }
  if (val == 'C' || val == 'CONDITIONAL') { return PetStatus.conditional; }
  return PetStatus.none;
}

Color getBadgeBgColor(CafeState state) {
  if (state == CafeState.open) { return Colors.green.withValues(alpha: 0.15); }
  if (state == CafeState.closingSoon) { return Colors.orange.withValues(alpha: 0.15); }
  if (state == CafeState.opensSoon) { return Colors.blue.withValues(alpha: 0.15); }
  if (state == CafeState.closed) { return Colors.red.withValues(alpha: 0.15); }
  return Colors.grey.withValues(alpha: 0.15);
}

Color getBadgeTextColor(CafeState state) {
  if (state == CafeState.open) { return Colors.green.shade600; }
  if (state == CafeState.closingSoon) { return Colors.orange.shade800; }
  if (state == CafeState.opensSoon) { return Colors.blue.shade700; }
  if (state == CafeState.closed) { return Colors.red.shade600; }
  return Colors.grey.shade600;
}

String formatStampTimestamp(String isoString) {
  try {
    final d = DateTime.parse(isoString);
    final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
    final minutePad = d.minute < 10 ? '0${d.minute}' : '${d.minute}';
    final ampm = d.hour >= 12 ? 'PM' : 'AM';
    final hourDisplay = d.hour > 12 ? d.hour - 12 : (d.hour == 0 ? 12 : d.hour);
    return '${months[d.month - 1]} ${d.day}, ${d.year} • $hourDisplay:$minutePad $ampm';
  } catch (e) { return 'Unknown Timestamp'; }
}

String formatNoteDate(DateTime d) {
  final months = ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'];
  return '${months[d.month - 1]} ${d.day}, ${d.year}';
}

String getDisplayDateForPill(DateTime date) {
  final now = DateTime.now(); final today = DateTime(now.year, now.month, now.day); final aDate = DateTime(date.year, date.month, date.day);
  if (aDate == today) { return "Today"; }
  if (aDate == today.subtract(const Duration(days: 1))) { return "Yesterday"; }
  return formatNoteDate(date);
}

class _TimeData {
  final int hour;
  final int minute;
  const _TimeData(this.hour, this.minute);
}

class PinNoteEntry {
  final DateTime date;
  final String text;
  final int originalIndex;
  PinNoteEntry(this.date, this.text, this.originalIndex);
}

class CafePinNotesGroup {
  final String cafeName;
  final List<PinNoteEntry> entries;
  CafePinNotesGroup(this.cafeName, this.entries);
}

class CafeStampGroup {
  final String cafeName;
  final List<DateTime> stampDates;
  CafeStampGroup(this.cafeName, this.stampDates);
}

class Cafe {
  final String name;
  final String address;
  final double rating;
  final int reviews;
  final String phone;
  final String businessHours;
  final double latitude;
  final double longitude;
  final String mapDirectionsUrl;
  final String instagramUrl;
  final PetStatus petStatus;
  final String imageUrl;

  const Cafe({
    required this.name, required this.address, required this.rating, required this.reviews, 
    required this.phone, required this.businessHours, required this.latitude, required this.longitude, 
    required this.mapDirectionsUrl, required this.instagramUrl, required this.petStatus, required this.imageUrl
  });

  _TimeData _parseTime(Match match) {
    int hour = int.parse(match.group(1)!);
    int minute = match.group(2) != null ? int.parse(match.group(2)!) : 0;
    String? ampm = match.group(3)?.toLowerCase().replaceAll('.', '');
    if (ampm != null) {
      if (ampm == 'pm' && hour != 12) { hour += 12; }
      if (ampm == 'am' && hour == 12) { hour = 0; }
    }
    return _TimeData(hour, minute);
  }

  CafeStatus getLiveStatus() {
    final cleanHours = businessHours.toLowerCase();
    if (cleanHours.contains('hours not listed') || cleanHours.contains('n/a')) { return const CafeStatus(CafeState.unknown, 'Hours Not Listed'); }

    final weekDays = ['monday', 'tuesday', 'wednesday', 'thursday', 'friday', 'saturday', 'sunday'];
    final now = DateTime.now();

    List<DateTime>? parseHours(String dayStr, DateTime refDate) {
      String lineStr = '';
      if (cleanHours.contains('opens daily:')) {
        lineStr = cleanHours.replaceFirst('opens daily:', '').trim();
      } else {
        final lines = cleanHours.split('\n');
        for (var line in lines) {
          if (line.trim().startsWith(dayStr)) {
            final firstColon = line.indexOf(':');
            if (firstColon != -1) { lineStr = line.substring(firstColon + 1).trim(); }
            break;
          }
        }
        if (lineStr.isEmpty && lines.length == 1) {
          final firstColon = lines[0].indexOf(':');
          if (firstColon == -1 || lines[0].substring(0, firstColon).contains(RegExp(r'\d'))) { lineStr = lines[0].trim(); }
          else { lineStr = lines[0].substring(firstColon + 1).trim(); }
        }
      }

      if (lineStr.isEmpty || lineStr.contains('closed')) { return null; }
      if (lineStr.contains('24 hours')) { return [DateTime(refDate.year, refDate.month, refDate.day, 0, 0), DateTime(refDate.year, refDate.month, refDate.day, 23, 59, 59)]; }

      final matches = RegExp(r'(\d{1,2})(?::(\d{2}))?\s*(a\.?m\.?|p\.?m\.?)?', caseSensitive: false).allMatches(lineStr).toList();
      if (matches.length >= 2) {
        try {
          var o = _parseTime(matches.first);
          var c = _parseTime(matches.last);
          if (matches.first.group(3) == null && o.hour >= 1 && o.hour <= 5) { o = _TimeData(o.hour + 12, o.minute); }
          if (matches.last.group(3) == null && c.hour >= 1 && c.hour <= 11) { c = _TimeData(c.hour + 12, c.minute); }
          var oDt = DateTime(refDate.year, refDate.month, refDate.day, o.hour, o.minute);
          var cDt = DateTime(refDate.year, refDate.month, refDate.day, c.hour, c.minute);
          if (cDt.isBefore(oDt) || cDt.isAtSameMomentAs(oDt)) { cDt = cDt.add(const Duration(days: 1)); }
          return [oDt, cDt];
        } catch (_) { return null; }
      }
      return null;
    }

    final todayStr = weekDays[now.weekday - 1];
    final yIndex = (now.weekday - 2) < 0 ? 6 : now.weekday - 2;
    final yHours = parseHours(weekDays[yIndex], now.subtract(const Duration(days: 1)));

    if (yHours != null && now.isBefore(yHours[1])) {
      final diff = yHours[1].difference(now);
      if (diff.inMinutes <= 30 && diff.inMinutes > 0) { return CafeStatus(CafeState.closingSoon, 'Closes in ${diff.inMinutes}m'); }
      return const CafeStatus(CafeState.open, 'Open Now');
    }

    final tHours = parseHours(todayStr, now);
    if (tHours != null && (now.isAfter(tHours[0]) || now.isAtSameMomentAs(tHours[0])) && now.isBefore(tHours[1])) {
      final diff = tHours[1].difference(now);
      if (diff.inMinutes <= 30 && diff.inMinutes > 0) { return CafeStatus(CafeState.closingSoon, 'Closes in ${diff.inMinutes}m'); }
      return const CafeStatus(CafeState.open, 'Open Now');
    }

    for (int i = 0; i <= 7; i++) {
      final d = now.add(Duration(days: i));
      final h = parseHours(weekDays[d.weekday - 1], d);
      if (h != null && h[0].isAfter(now)) {
        final diff = h[0].difference(now);
        if (diff.inMinutes <= 60 && diff.inMinutes > 0) { return CafeStatus(CafeState.opensSoon, 'Opens in ${diff.inMinutes}m'); }
        final hr12 = h[0].hour > 12 ? h[0].hour - 12 : (h[0].hour == 0 ? 12 : h[0].hour);
        final mStr = h[0].minute == 0 ? '' : ':${h[0].minute.toString().padLeft(2, '0')}';
        final am = h[0].hour >= 12 ? 'PM' : 'AM';
        final tStr = '$hr12$mStr $am';
        if (h[0].day == now.day) { return CafeStatus(CafeState.closed, 'Opens at $tStr'); }
        else if (h[0].day == now.add(const Duration(days: 1)).day) { return CafeStatus(CafeState.closed, 'Opens tmrw $tStr'); } 
        else { return CafeStatus(CafeState.closed, 'Opens ${['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'][h[0].weekday - 1]} $tStr'); }
      }
    }
    return const CafeStatus(CafeState.closed, 'Closed');
  }
}

// ============================================================================
// ROOT APPLICATION
// ============================================================================

class BlackPinApp extends StatelessWidget {
  const BlackPinApp({super.key});

  @override
  Widget build(BuildContext context) {
    return ValueListenableBuilder<ThemeMode>(
      valueListenable: themeNotifier,
      builder: (context, ThemeMode mode, child) {
        return MaterialApp(
          debugShowCheckedModeBanner: false, 
          title: 'BLACKPIN', 
          themeMode: mode,
          theme: ThemeData(
            useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.black, brightness: Brightness.light),
            scaffoldBackgroundColor: Colors.grey.shade50, appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white),
            bottomNavigationBarTheme: const BottomNavigationBarThemeData(backgroundColor: Colors.black, selectedItemColor: Colors.white, unselectedItemColor: Colors.white54),
          ),
          darkTheme: ThemeData(
            useMaterial3: true, colorScheme: ColorScheme.fromSeed(seedColor: Colors.white, brightness: Brightness.dark, surface: const Color(0xFF1A1A1A), onSurface: Colors.white),
            scaffoldBackgroundColor: Colors.black, appBarTheme: const AppBarTheme(backgroundColor: Colors.black, foregroundColor: Colors.white, elevation: 0), dividerColor: Colors.grey.shade800,
            bottomNavigationBarTheme: BottomNavigationBarThemeData(backgroundColor: const Color(0xFF1A1A1A), selectedItemColor: Colors.white, unselectedItemColor: Colors.grey.shade600),
          ),
          home: const HomeScreen(),
        );
      },
    );
  }
}

// ============================================================================
// REUSABLE CAFE CARD WIDGET
// ============================================================================
class CafeListTile extends StatelessWidget {
  final Cafe cafe;
  final Position? userPos;
  final bool isDark;
  final bool isFav;
  final bool isVisited;
  final VoidCallback onFav;
  final VoidCallback onTap;

  const CafeListTile({super.key, required this.cafe, required this.userPos, required this.isDark, required this.isFav, required this.isVisited, required this.onFav, required this.onTap});

  @override
  Widget build(BuildContext context) {
    final live = cafe.getLiveStatus();
    final bg = getBadgeBgColor(live.state);
    final tc = getBadgeTextColor(live.state);
    
    String distStr = "";
    if (userPos != null) { 
      distStr = ' • ${(Geolocator.distanceBetween(userPos!.latitude, userPos!.longitude, cafe.latitude, cafe.longitude) / 1000).toStringAsFixed(1)}km'; 
    }

    return Card(
      color: isDark ? Theme.of(context).colorScheme.surface : Colors.white, 
      elevation: 1, 
      margin: const EdgeInsets.only(bottom: 10),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isDark ? Colors.grey.shade900 : Colors.grey.shade200)),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        leading: ClipRRect(
          borderRadius: BorderRadius.circular(10), 
          child: Container(
            height: 46, width: 46, color: isDark ? Colors.white : Colors.black87, 
            child: cafe.imageUrl.isNotEmpty 
                ? Image.network(cafe.imageUrl, fit: BoxFit.cover, errorBuilder: (c, e, s) => Icon(Icons.local_cafe, color: isDark ? Colors.black : Colors.white)) 
                : Icon(Icons.local_cafe, color: isDark ? Colors.black : Colors.white)
          )
        ),
        title: Row(
          children: [
            Expanded(child: Text(cafe.name, style: TextStyle(fontWeight: FontWeight.bold, fontSize: 15, color: Theme.of(context).colorScheme.onSurface))),
            if (isVisited) 
              Container(
                margin: const EdgeInsets.only(right: 6), padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                decoration: BoxDecoration(color: Colors.blue.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(4)), 
                child: const Text('VISITED', style: TextStyle(fontSize: 8, fontWeight: FontWeight.bold, color: Colors.blue))
              ),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
              decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(6)), 
              child: Text(live.displayMessage.toUpperCase(), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: tc))
            ),
          ]
        ),
        subtitle: Padding(
          padding: const EdgeInsets.only(top: 2.0), 
          child: Row(
            children: [
              Expanded(child: Text('${cafe.rating > 0 ? "⭐ ${cafe.rating} (${cafe.reviews})" : "No rating"}$distStr • ${cafe.address}', maxLines: 1, overflow: TextOverflow.ellipsis, style: TextStyle(color: isDark ? Colors.white70 : Colors.black87, fontSize: 13))),
              if (cafe.petStatus == PetStatus.friendly) 
                Padding(padding: const EdgeInsets.only(left: 4.0), child: Icon(Icons.pets, size: 14, color: isDark ? Colors.green.shade400 : Colors.green.shade700)),
              if (cafe.petStatus == PetStatus.conditional) 
                Padding(padding: const EdgeInsets.only(left: 4.0), child: Icon(Icons.pets, size: 14, color: isDark ? Colors.orange.shade400 : Colors.orange.shade700)),
            ]
          )
        ),
        trailing: IconButton(icon: Icon(isFav ? Icons.favorite : Icons.favorite_border, color: isFav ? Colors.red : Colors.grey), padding: EdgeInsets.zero, constraints: const BoxConstraints(), onPressed: onFav),
        onTap: onTap,
      ),
    );
  }
}

// ============================================================================
// HOME SCREEN
// ============================================================================

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});
  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final TextEditingController _searchController = TextEditingController();
  late SharedPreferences _prefs;
  List<String> bookmarkedCafes = [];
  List<String> visitedCafes = [];
  List<Cafe> allCafes = [];
  List<Cafe> displayedCafes = [];
  
  bool isLoading = true;
  String searchNavbarQuery = "";
  String selectedSortOption = "A-Z"; 
  String selectedAreaFilter = "All Areas"; 
  
  int _petFilterIndex = 0; 
  final List<String> _petFilterLabels = ["🐾 Pet Filter", "🐾 Fully Friendly", "🐾 Pets (Conditional)", "🚫 No Pets"];
  
  bool pillOpenNow = false;
  bool pillBookmarked = false;
  bool pillVisited = false;
  bool pillUnvisited = false;
  
  int _bottomNavIndex = 0; 
  bool _isDevMode = false;
  bool _isDevMenuUnlocked = false;
  int _secretTapCount = 0;
  
  Position? userPosition;
  GoogleMapController? _mapController;
  LatLng _currentMapTarget = const LatLng(5.3950, 100.3150);
  double _currentMapZoom = 11.5;
  double _currentMapBearing = 0.0; 
  Cafe? _selectedMapCafe;
  ScreenCoordinate? _popupCoordinate;
  bool _isFetchingCoordinate = false;

  static const String _darkMapStyle = '[{"elementType":"geometry","stylers":[{"color":"#1c1c1e"}]},{"elementType":"labels.icon","stylers":[{"visibility":"off"}]},{"elementType":"labels.text.fill","stylers":[{"color":"#8e8e93"}]},{"elementType":"labels.text.stroke","stylers":[{"color":"#1c1c1e"}]},{"featureType":"administrative","stylers":[{"color":"#3a3a3c"}]},{"featureType":"administrative.country","elementType":"labels.text.fill","stylers":[{"color":"#aeaeb2"}]},{"featureType":"administrative.locality","elementType":"labels.text.fill","stylers":[{"color":"#c7c7cc"}]},{"featureType":"poi","elementType":"labels.text.fill","stylers":[{"color":"#8e8e93"}]},{"featureType":"poi.park","elementType":"geometry","stylers":[{"color":"#152b1e"}]},{"featureType":"poi.park","elementType":"labels.text.fill","stylers":[{"color":"#63e6be"}]},{"featureType":"landscape.natural","elementType":"geometry","stylers":[{"color":"#1a241b"}]},{"featureType":"road","elementType":"geometry.fill","stylers":[{"color":"#2c2c2e"}]},{"featureType":"road","elementType":"labels.text.fill","stylers":[{"color":"#aeaeb2"}]},{"featureType":"road.arterial","elementType":"geometry","stylers":[{"color":"#3a3a3c"}]},{"featureType":"road.highway","elementType":"geometry","stylers":[{"color":"#48484a"}]},{"featureType":"transit","elementType":"labels.text.fill","stylers":[{"color":"#8e8e93"}]},{"featureType":"water","elementType":"geometry","stylers":[{"color":"#0d1b2a"}]},{"featureType":"water","elementType":"labels.text.fill","stylers":[{"color":"#457b9d"}]}]';

  final List<Map<String, dynamic>> _rankMatrix = [
    {'title': 'Casual Drinker', 'icon': Icons.local_cafe, 'color': Colors.brown.shade400},
    {'title': 'Cafe Hopper', 'icon': Icons.directions_walk, 'color': Colors.green.shade500},
    {'title': 'Bean Explorer', 'icon': Icons.explore, 'color': Colors.teal.shade500},
    {'title': 'Local Regular', 'icon': Icons.star_rounded, 'color': Colors.blueAccent},
    {'title': 'Caffeine Addict', 'icon': Icons.bolt, 'color': Colors.deepPurpleAccent},
    {'title': 'Penang Barista', 'icon': Icons.workspace_premium, 'color': Colors.amber.shade600},
  ];

  @override
  void initState() {
    super.initState();
    _initPreferences().then((_) async {
      await _loadCachedCafes(); 
      await _fetchCafesFromSheet(); 
    });
    _checkLocationSilently(); 
  }

  List<String> get validBookmarkedCafes {
    final Set<String> validNames = allCafes.map((c) => c.name.trim()).toSet();
    return bookmarkedCafes.where((name) => validNames.contains(name.trim())).toList();
  }

  List<String> get validVisitedCafes {
    final Set<String> validNames = allCafes.map((c) => c.name.trim()).toSet();
    return visitedCafes.where((name) => validNames.contains(name.trim())).toList();
  }

  int get validTotalPassportStamps {
    int count = 0;
    final Set<String> validNames = allCafes.map((c) => c.name.trim()).toSet();
    for (String key in _prefs.getKeys()) {
      if (key.startsWith('visit_logs_')) {
        String cafeName = key.replaceFirst('visit_logs_', '').trim();
        if (validNames.contains(cafeName)) { 
          count += (_prefs.getStringList(key) ?? []).length; 
        }
      }
    }
    return count;
  }

  Future<void> _initPreferences() async {
    _prefs = await SharedPreferences.getInstance();
    _isDevMode = _prefs.getBool('dev_mode') ?? false; 
    if (_isDevMode) { 
      _isDevMenuUnlocked = true; 
    }
    setState(() {
      bookmarkedCafes = _prefs.getStringList('saved_bookmarks') ?? [];
      visitedCafes = _prefs.getStringList('saved_visited') ?? [];
    });
  }

  Future<void> _checkLocationSilently() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) { 
      return; 
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.whileInUse || permission == LocationPermission.always) {
      final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
      if (mounted) { 
        setState(() { 
          userPosition = position; 
          processFiltersAndSorting(); 
        }); 
      }
    }
  }

  Future<void> _getUserLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) {
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Please enable GPS.'))); }
      return;
    }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) {
      permission = await Geolocator.requestPermission();
      if (permission == LocationPermission.denied) { return; }
    }
    if (permission == LocationPermission.deniedForever) { return; }
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    if (mounted) { 
      setState(() { 
        userPosition = position; 
        processFiltersAndSorting(); 
      }); 
    }
  }

  Future<void> _updatePopupCoordinate() async {
    if (_mapController == null || _selectedMapCafe == null || _isFetchingCoordinate) { 
      return; 
    }
    _isFetchingCoordinate = true;
    try {
      final coord = await _mapController!.getScreenCoordinate(LatLng(_selectedMapCafe!.latitude, _selectedMapCafe!.longitude));
      if (mounted && _selectedMapCafe != null) { 
        setState(() { 
          _popupCoordinate = coord; 
        }); 
      }
    } catch (e) { 
      /* ignore */ 
    } finally { 
      _isFetchingCoordinate = false; 
    }
  }

  Future<void> toggleBookmark(String name) async {
    setState(() {
      if (bookmarkedCafes.contains(name)) { 
        bookmarkedCafes.remove(name); 
      } else { 
        bookmarkedCafes.add(name); 
      }
    });
    await _prefs.setStringList('saved_bookmarks', bookmarkedCafes);
    processFiltersAndSorting();
  }

  Future<void> toggleVisited(String name, bool status) async {
    setState(() {
      if (status) {
        if (!visitedCafes.contains(name)) {
          visitedCafes.add(name);
          List<String> stamps = _prefs.getStringList('visit_logs_$name') ?? [];
          if (stamps.isEmpty) { 
            stamps.add(jsonEncode({'date': DateTime.now().toIso8601String()})); 
            _prefs.setStringList('visit_logs_$name', stamps); 
          }
        }
      } else {
        visitedCafes.remove(name);
        _prefs.remove('visit_logs_$name'); 
      }
    });
    await _prefs.setStringList('saved_visited', visitedCafes);
    _initPreferences().then((_) { processFiltersAndSorting(); });
  }

  Future<void> _loadCachedCafes() async {
    final String? cachedCsv = _prefs.getString('cached_cafe_csv');
    if (cachedCsv != null && cachedCsv.isNotEmpty) {
      try {
        final List<List<dynamic>> csvTable = const CsvToListConverter().convert(cachedCsv);
        List<Cafe> parsed = [];
        for (var i = 1; i < csvTable.length; i++) {
          var row = csvTable[i];
          if (row.length >= 4 && row[2].toString().trim().isNotEmpty) {
            parsed.add(Cafe(
              mapDirectionsUrl: row[1].toString().trim(), 
              name: row[2].toString().trim(), 
              address: row[3].toString().trim(),
              rating: double.tryParse(row[4].toString().trim()) ?? 0.0, 
              reviews: int.tryParse(row[5].toString().trim()) ?? 0,
              phone: row[6].toString().trim(), 
              businessHours: row[7].toString().trim(),
              latitude: double.tryParse(row[8].toString().trim()) ?? 0.0, 
              longitude: double.tryParse(row[9].toString().trim()) ?? 0.0,
              instagramUrl: row[10].toString().trim(), 
              petStatus: parsePetStatus(row[11].toString()), 
              imageUrl: row.length > 12 ? row[12].toString().trim() : '',
            ));
          }
        }
        if (mounted) { 
          setState(() { 
            allCafes = parsed; 
            isLoading = false; 
            processFiltersAndSorting(); 
          }); 
        }
      } catch (e) { 
        debugPrint(e.toString()); 
      }
    }
  }

  Future<void> _fetchCafesFromSheet() async {
    if (allCafes.isEmpty) { 
      setState(() { isLoading = true; }); 
    }
    try {
      final response = await http.get(Uri.parse('https://docs.google.com/spreadsheets/d/e/2PACX-1vQpLMU6yF9zDIR27_d7BpA5sG_PiwSiQ4XlUse8V9ii0V6c4YocftYnM2tbZK7CkdqVf-wmS88tbyfl/pub?output=csv&t=${DateTime.now().millisecondsSinceEpoch}'));
      if (response.statusCode == 200) {
        await _prefs.setString('cached_cafe_csv', utf8.decode(response.bodyBytes));
        await _loadCachedCafes();
      } else if (mounted) { 
        setState(() { isLoading = false; }); 
      }
    } catch (e) {
      if (mounted) { 
        setState(() { isLoading = false; }); 
      }
    }
  }

  void processFiltersAndSorting() {
    setState(() {
      var filtered = allCafes.where((cafe) {
        final matchesSearch = cafe.name.toLowerCase().contains(searchNavbarQuery.toLowerCase()) || cafe.address.toLowerCase().contains(searchNavbarQuery.toLowerCase());
        bool matchesArea = selectedAreaFilter == "All Areas" || cafe.address.toLowerCase().contains(selectedAreaFilter.toLowerCase().replaceAll("george town", "georgetown"));
        
        if (_petFilterIndex == 1 && cafe.petStatus != PetStatus.friendly) { return false; }
        if (_petFilterIndex == 2 && cafe.petStatus != PetStatus.conditional && cafe.petStatus != PetStatus.friendly) { return false; }
        if (_petFilterIndex == 3 && cafe.petStatus != PetStatus.none) { return false; }
        if (pillOpenNow && !cafe.getLiveStatus().isOpen) { return false; }
        if (pillBookmarked && !bookmarkedCafes.contains(cafe.name)) { return false; }
        if (pillVisited && !visitedCafes.contains(cafe.name) && !pillUnvisited) { return false; }
        if (pillUnvisited && visitedCafes.contains(cafe.name) && !pillVisited) { return false; }
        
        return matchesSearch && matchesArea;
      }).toList();

      if (selectedSortOption == "Nearest to Me" && userPosition != null) { 
        filtered.sort((a, b) => Geolocator.distanceBetween(userPosition!.latitude, userPosition!.longitude, a.latitude, a.longitude).compareTo(Geolocator.distanceBetween(userPosition!.latitude, userPosition!.longitude, b.latitude, b.longitude))); 
      } 
      else if (selectedSortOption == "A-Z") { 
        filtered.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())); 
      } 
      else if (selectedSortOption == "Z-A") { 
        filtered.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())); 
      } 
      else if (selectedSortOption == "Reviews") { 
        filtered.sort((a, b) => b.reviews.compareTo(a.reviews)); 
      } 
      else if (selectedSortOption == "Rating") { 
        filtered.sort((a, b) => b.rating.compareTo(a.rating)); 
      }
      displayedCafes = filtered;
    });
  }

  void _shareMyHitlist() {
    final validHitlist = bookmarkedCafes.where((name) => allCafes.map((c) => c.name.trim()).toSet().contains(name.trim())).toList();
    if (validHitlist.isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("Hitlist is empty!"))); 
      return; 
    }
    
    List<String> selectedToShare = List.from(validHitlist);

    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            bool isAllSelected = selectedToShare.length == validHitlist.length;
            return FractionallySizedBox(
              heightFactor: 0.75, 
              child: Column(
                children: [
                  const SizedBox(height: 12), 
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))), 
                  const SizedBox(height: 16),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 20), 
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween, 
                      children: [
                        Text("Share Hitlist", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)), 
                        TextButton(
                          onPressed: () { 
                            setModalState(() { 
                              if (isAllSelected) { selectedToShare.clear(); } 
                              else { selectedToShare = List.from(validHitlist); } 
                            }); 
                          }, 
                          child: Text(isAllSelected ? "Deselect All" : "Select All", style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.blueAccent))
                        )
                      ] 
                    )
                  ),
                  const Divider(height: 1),
                  Expanded(
                    child: ListView.builder(
                      itemCount: validHitlist.length, 
                      itemBuilder: (context, index) { 
                        return CheckboxListTile(
                          dense: true, 
                          visualDensity: VisualDensity.compact, 
                          activeColor: Colors.blueAccent, 
                          title: Text(validHitlist[index], style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)), 
                          value: selectedToShare.contains(validHitlist[index]), 
                          onChanged: (bool? val) { 
                            setModalState(() { 
                              if (val == true) { selectedToShare.add(validHitlist[index]); } 
                              else { selectedToShare.remove(validHitlist[index]); } 
                            }); 
                          }
                        ); 
                      }
                    )
                  ),
                  Padding(
                    padding: const EdgeInsets.all(16.0), 
                    child: SizedBox(
                      width: double.infinity, 
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: Colors.blueAccent, 
                          foregroundColor: Colors.white, 
                          padding: const EdgeInsets.symmetric(vertical: 14), 
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                          disabledBackgroundColor: Colors.grey.shade400
                        ), 
                        onPressed: selectedToShare.isEmpty ? null : () { 
                          String shareText = "☕ My BLACKPIN Hitlist:\n\n"; 
                          int counter = 1; 
                          for (var cName in validHitlist) { 
                            if (selectedToShare.contains(cName)) { 
                              try { 
                                final cafe = allCafes.firstWhere((c) => c.name.trim() == cName.trim()); 
                                shareText += "$counter. ${cafe.name}\n📍 ${cafe.address}\n🗺️ Directions: ${cafe.mapDirectionsUrl}\n\n"; 
                                counter++; 
                              } catch (e) { /* ignore */ } 
                            } 
                          } 
                          shareText += "---\n📍 Pinned via BLACKPIN"; 
                          // ignore: deprecated_member_use
                          Share.share(shareText); 
                          Navigator.pop(context); 
                        }, 
                        child: Text("Share ${selectedToShare.length} Cafes", style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold))
                      )
                    )
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  void _showRankInfo() {
    int totalCafes = allCafes.isEmpty ? 1 : allCafes.length;
    List<int> thresholds = [0, (totalCafes * 0.08).ceil(), (totalCafes * 0.19).ceil(), (totalCafes * 0.33).ceil(), (totalCafes * 0.51).ceil(), (totalCafes * 0.73).ceil()];
    
    showModalBottomSheet(
      context: context, 
      isScrollControlled: true, 
      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))), 
              const SizedBox(height: 16),
              Text("Caffeine Passport Ranks", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24.0, vertical: 8.0), 
                child: Text("Progression is dynamic! Thresholds automatically scale.", textAlign: TextAlign.center, style: TextStyle(fontSize: 12, color: Colors.grey.shade600))
              ), 
              const SizedBox(height: 8),
              ..._rankMatrix.asMap().entries.map((entry) { 
                return ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(10), 
                    decoration: BoxDecoration(color: entry.value['color'].withValues(alpha: 0.15), shape: BoxShape.circle), 
                    child: Icon(entry.value['icon'], color: entry.value['color'])
                  ), 
                  title: Text(entry.value['title'], style: const TextStyle(fontWeight: FontWeight.bold)), 
                  subtitle: Text("${thresholds[entry.key]} unique cafes required")
                ); 
              }),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Column(
          children: [
            Text(_bottomNavIndex == 2 ? 'CAFFEINE PASSPORT' : 'BLACKPIN', style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 4.0, fontSize: 18)),
            Text(_bottomNavIndex == 2 ? 'YOUR EXPLORATION RECORD' : 'FIND YOUR BLACK COFFEE', style: const TextStyle(fontWeight: FontWeight.w400, letterSpacing: 2.5, fontSize: 10, color: Colors.white70)),
          ],
        ),
        centerTitle: true,
        actions: [
          if (_bottomNavIndex == 2)
            PopupMenuButton<ThemeMode>(
              icon: const Icon(Icons.palette_outlined, color: Colors.white),
              onSelected: (mode) { themeNotifier.value = mode; },
              itemBuilder: (c) => [
                const PopupMenuItem(value: ThemeMode.system, child: Row(children: [Icon(Icons.brightness_auto, size: 20), SizedBox(width: 10), Text('System Default')])),
                const PopupMenuItem(value: ThemeMode.light, child: Row(children: [Icon(Icons.light_mode, size: 20), SizedBox(width: 10), Text('Light Mode')])),
                const PopupMenuItem(value: ThemeMode.dark, child: Row(children: [Icon(Icons.dark_mode, size: 20), SizedBox(width: 10), Text('Dark Mode')])),
              ],
            )
          else
            IconButton(
              icon: const Icon(Icons.refresh), 
              onPressed: () { 
                setState(() { isLoading = true; }); 
                _fetchCafesFromSheet(); 
              }
            )
        ],
      ),
      body: isLoading 
          ? const Center(child: CircularProgressIndicator(color: Colors.blueAccent)) 
          : _bottomNavIndex == 2 ? _buildProfileScreen(theme) : _buildListOrMapView(theme),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _bottomNavIndex,
        onTap: (index) { 
          setState(() { 
            _bottomNavIndex = index; 
            if (index == 1 && userPosition == null) { 
              _getUserLocation(); 
            } 
          }); 
        },
        items: const [
          BottomNavigationBarItem(icon: Icon(Icons.view_list), label: 'Discover'), 
          BottomNavigationBarItem(icon: Icon(Icons.map), label: 'Map'), 
          BottomNavigationBarItem(icon: Icon(Icons.person), label: 'Profile')
        ],
      ),
    );
  }

  Widget _buildFilterPill(String label, bool active, VoidCallback onTap) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: InkWell(
        onTap: onTap,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          decoration: BoxDecoration(color: active ? Colors.blueAccent : Colors.grey.withValues(alpha: 0.2), borderRadius: BorderRadius.circular(20)),
          child: Text(label, style: TextStyle(color: active ? Colors.white : null, fontWeight: FontWeight.bold, fontSize: 13)),
        ),
      ),
    );
  }

  Widget _buildListOrMapView(ThemeData theme) {
    bool isDark = theme.brightness == Brightness.dark;
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.all(16.0),
          child: SearchBar(
            controller: _searchController, 
            hintText: 'Search...',
            leading: const Icon(Icons.search), 
            trailing: [
              if (searchNavbarQuery.isNotEmpty) 
                IconButton(
                  icon: const Icon(Icons.close), 
                  onPressed: () { 
                    setState(() { _searchController.clear(); searchNavbarQuery = ""; processFiltersAndSorting(); }); 
                  }
                )
            ],
            onChanged: (val) { 
              setState(() { searchNavbarQuery = val; processFiltersAndSorting(); }); 
            },
          ),
        ),
        SingleChildScrollView(
          scrollDirection: Axis.horizontal, 
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Row(
            children: [
              _buildFilterPill(_petFilterLabels[_petFilterIndex], _petFilterIndex != 0, () { 
                setState(() { _petFilterIndex = (_petFilterIndex + 1) % 4; processFiltersAndSorting(); }); 
              }),
              _buildFilterPill("☕ Open", pillOpenNow, () { 
                setState(() { pillOpenNow = !pillOpenNow; processFiltersAndSorting(); }); 
              }),
              _buildFilterPill("❤️ Hitlist", pillBookmarked, () { 
                setState(() { pillBookmarked = !pillBookmarked; processFiltersAndSorting(); }); 
              }),
              _buildFilterPill("✅ Visited", pillVisited, () { 
                setState(() { pillVisited = !pillVisited; processFiltersAndSorting(); }); 
              }),
            ]
          ),
        ),
        const SizedBox(height: 10),
        Expanded(
          child: _bottomNavIndex == 1 
              ? _buildMap() 
              : ListView.builder(
                  itemCount: displayedCafes.length, 
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemBuilder: (c, i) => CafeListTile(
                    cafe: displayedCafes[i], 
                    userPos: userPosition, 
                    isDark: isDark,
                    isFav: bookmarkedCafes.contains(displayedCafes[i].name), 
                    isVisited: visitedCafes.contains(displayedCafes[i].name),
                    onFav: () { 
                      toggleBookmark(displayedCafes[i].name); 
                    },
                    onTap: () {
                      Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(
                        cafe: displayedCafes[i], 
                        isBookmarked: bookmarkedCafes.contains(displayedCafes[i].name), 
                        isVisited: visitedCafes.contains(displayedCafes[i].name),
                        initialNotes: _prefs.getStringList('notes_${displayedCafes[i].name}') ?? [],
                        onBookmarkChanged: () => toggleBookmark(displayedCafes[i].name),
                        onVisitedChanged: (status) => toggleVisited(displayedCafes[i].name, status),
                        onNoteAdded: (text, date) async {
                          List<String> notes = _prefs.getStringList('notes_${displayedCafes[i].name}') ?? [];
                          notes.add(jsonEncode({'date': date, 'text': text}));
                          await _prefs.setStringList('notes_${displayedCafes[i].name}', notes);
                        },
                        onNoteDeleted: (idx) async {
                          List<String> notes = _prefs.getStringList('notes_${displayedCafes[i].name}') ?? [];
                          if (idx >= 0 && idx < notes.length) { 
                            notes.removeAt(idx); 
                            await _prefs.setStringList('notes_${displayedCafes[i].name}', notes); 
                          }
                        }
                      ))).then((_) { 
                        _initPreferences().then((_) { processFiltersAndSorting(); }); 
                      });
                    },
                  ),
                )
        )
      ],
    );
  }

  Widget _buildMap() {
    bool isDark = Theme.of(context).brightness == Brightness.dark;
    double pixelRatio = Platform.isAndroid ? MediaQuery.of(context).devicePixelRatio : 1.0;
    
    IconData smartIcon = Icons.location_searching;
    Color smartIconColor = isDark ? Colors.white70 : Colors.black87;
    String smartTooltip = "Center on My Location";
    
    VoidCallback smartAction = () async {
      await _getUserLocation();
      if (userPosition != null && _mapController != null) {
        _mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(userPosition!.latitude, userPosition!.longitude), zoom: 15.0, bearing: 0.0)));
      }
    };

    bool isRotated = _currentMapBearing.abs() > 1.0; 
    bool isCentered = false;

    if (userPosition != null) {
      final double distance = Geolocator.distanceBetween(_currentMapTarget.latitude, _currentMapTarget.longitude, userPosition!.latitude, userPosition!.longitude);
      isCentered = distance < 60; 
    }

    if (isRotated) {
      smartIcon = Icons.explore;
      smartIconColor = Colors.redAccent;
      smartTooltip = "Reset Map North";
      smartAction = () {
        if (_mapController != null) {
          _mapController!.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: _currentMapTarget, zoom: _currentMapZoom, bearing: 0.0, tilt: 0.0)));
        }
      };
    } else if (isCentered) {
      smartIcon = Icons.my_location;
      smartIconColor = Colors.blueAccent;
      smartTooltip = "Location Locked";
    }

    return Stack(
      children: [
        GoogleMap(
          initialCameraPosition: const CameraPosition(target: LatLng(5.3950, 100.3150), zoom: 11.5),
          style: isDark ? _darkMapStyle : null, 
          myLocationEnabled: userPosition != null, 
          myLocationButtonEnabled: false, 
          mapToolbarEnabled: false, 
          zoomControlsEnabled: true,
          onMapCreated: (c) { _mapController = c; },
          onCameraMove: (p) { 
            setState(() { 
              _currentMapTarget = p.target; 
              _currentMapZoom = p.zoom; 
              _currentMapBearing = p.bearing; 
            }); 
            if (_selectedMapCafe != null) { _updatePopupCoordinate(); } 
          },
          onCameraIdle: () { 
            if (_selectedMapCafe != null) { _updatePopupCoordinate(); } 
          },
          onTap: (_) { 
            setState(() { _selectedMapCafe = null; _popupCoordinate = null; }); 
          },
          markers: displayedCafes.map((c) => Marker(
            markerId: MarkerId(c.name), 
            position: LatLng(c.latitude, c.longitude), 
            onTap: () { 
              setState(() { _selectedMapCafe = c; }); 
              _updatePopupCoordinate(); 
              _mapController?.animateCamera(CameraUpdate.newCameraPosition(CameraPosition(target: LatLng(c.latitude, c.longitude), zoom: _currentMapZoom, bearing: _currentMapBearing))); 
            }
          )).toSet(),
        ),
        Positioned(
          top: 12, right: 12,
          child: FloatingActionButton.small(
            heroTag: 'map_btn', 
            backgroundColor: isDark ? const Color(0xFF2A2A2A) : Colors.white, 
            foregroundColor: smartIconColor, 
            tooltip: smartTooltip, 
            onPressed: smartAction, 
            child: Icon(smartIcon, size: 22)
          ),
        ),
        if (_selectedMapCafe != null && _popupCoordinate != null)
          Positioned(
            left: _popupCoordinate!.x / pixelRatio, top: _popupCoordinate!.y / pixelRatio,
            child: FractionalTranslation(
              translation: const Offset(-0.5, -1.0),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 40.0),
                child: GestureDetector(
                  onTap: () {
                    Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(
                      cafe: _selectedMapCafe!, 
                      isBookmarked: bookmarkedCafes.contains(_selectedMapCafe!.name), 
                      isVisited: visitedCafes.contains(_selectedMapCafe!.name),
                      initialNotes: _prefs.getStringList('notes_${_selectedMapCafe!.name}') ?? [],
                      onBookmarkChanged: () => toggleBookmark(_selectedMapCafe!.name), 
                      onVisitedChanged: (status) => toggleVisited(_selectedMapCafe!.name, status),
                      onNoteAdded: (text, date) async { 
                        List<String> notes = _prefs.getStringList('notes_${_selectedMapCafe!.name}') ?? []; 
                        notes.add(jsonEncode({'date': date, 'text': text})); 
                        await _prefs.setStringList('notes_${_selectedMapCafe!.name}', notes); 
                      },
                      onNoteDeleted: (idx) async { 
                        List<String> notes = _prefs.getStringList('notes_${_selectedMapCafe!.name}') ?? []; 
                        if (idx >= 0 && idx < notes.length) { 
                          notes.removeAt(idx); 
                          await _prefs.setStringList('notes_${_selectedMapCafe!.name}', notes); 
                        } 
                      }
                    ))).then((_) { 
                      _initPreferences().then((_) { processFiltersAndSorting(); }); 
                    });
                  },
                  child: Container(
                    width: 200, padding: const EdgeInsets.all(12), 
                    decoration: BoxDecoration(
                      color: isDark ? Theme.of(context).colorScheme.surface : Colors.white, 
                      borderRadius: BorderRadius.circular(14), 
                      boxShadow: [BoxShadow(color: Colors.black.withValues(alpha: 0.2), blurRadius: 10, offset: const Offset(0, 4))]
                    ),
                    child: Column(
                      mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_selectedMapCafe!.name, maxLines: 1, overflow: TextOverflow.ellipsis, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14)),
                        const SizedBox(height: 4), 
                        Text(_selectedMapCafe!.address, maxLines: 2, overflow: TextOverflow.ellipsis, style: const TextStyle(fontSize: 11, color: Colors.grey)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          )
      ],
    );
  }

  Widget _buildProfileScreen(ThemeData theme) {
    bool isDark = theme.brightness == Brightness.dark;
    int totalCafes = allCafes.isEmpty ? 1 : allCafes.length; 
    int visited = validVisitedCafes.length;
    
    List<int> thresholds = [0, (totalCafes * 0.08).ceil(), (totalCafes * 0.19).ceil(), (totalCafes * 0.33).ceil(), (totalCafes * 0.51).ceil(), (totalCafes * 0.73).ceil(), totalCafes];
    
    int currentLevel = 1;
    for (int i = 5; i >= 0; i--) { 
      if (visited >= thresholds[i]) { 
        currentLevel = i + 1; 
        break; 
      } 
    }
    
    double progress = 0.0;
    String progressText = "";
    
    if (currentLevel < 6) {
      int prevThreshold = thresholds[currentLevel - 1];
      int nextThreshold = thresholds[currentLevel];
      int cafesInLevel = visited - prevThreshold;
      int cafesNeededForLevel = nextThreshold - prevThreshold;
      progress = cafesNeededForLevel == 0 ? 1.0 : cafesInLevel / cafesNeededForLevel;
      progressText = "$visited / $nextThreshold cafes explored to reach ${_rankMatrix[currentLevel]['title']}";
    } else {
      int prevThreshold = thresholds[5];
      int nextThreshold = totalCafes;
      int cafesInLevel = visited - prevThreshold;
      int cafesNeededForLevel = nextThreshold - prevThreshold;
      if (visited >= totalCafes) { 
        progress = 1.0; 
        progressText = "All $totalCafes cafes explored! Ultimate Master."; 
      } else { 
        progress = cafesNeededForLevel == 0 ? 1.0 : cafesInLevel / cafesNeededForLevel; 
        progressText = "$visited / $totalCafes cafes explored to complete the passport!"; 
      }
    }
    
    String rankTitle = _rankMatrix[currentLevel - 1]['title'];
    IconData rankIcon = _rankMatrix[currentLevel - 1]['icon'];
    Color rankColor = _rankMatrix[currentLevel - 1]['color'];

    return SingleChildScrollView(
      padding: const EdgeInsets.all(16.0), 
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.05), blurRadius: 10, offset: const Offset(0, 4))]),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(gradient: LinearGradient(colors: [rankColor.withValues(alpha: 0.15), rankColor.withValues(alpha: 0.03)], begin: Alignment.topLeft, end: Alignment.bottomRight), borderRadius: BorderRadius.circular(16), border: Border.all(color: rankColor.withValues(alpha: 0.25))),
                child: InkWell(
                  borderRadius: BorderRadius.circular(16), 
                  onTap: _showRankInfo,
                  child: Container(
                    width: double.infinity, padding: const EdgeInsets.symmetric(vertical: 20, horizontal: 20),
                    child: Column(
                      children: [
                        Container(padding: const EdgeInsets.all(12), decoration: BoxDecoration(color: rankColor.withValues(alpha: 0.12), shape: BoxShape.circle), child: Icon(rankIcon, size: 36, color: rankColor)),
                        const SizedBox(height: 10), 
                        Text(rankTitle.toUpperCase(), style: TextStyle(fontSize: 18, fontWeight: FontWeight.w900, color: rankColor, letterSpacing: 1.5)), 
                        const SizedBox(height: 2), 
                        Text("Current Exploration Rank", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade600)), 
                        const SizedBox(height: 24),
                        ClipRRect(borderRadius: BorderRadius.circular(6), child: LinearProgressIndicator(value: progress, minHeight: 8, backgroundColor: isDark ? Colors.black38 : Colors.white60, color: rankColor)), 
                        const SizedBox(height: 8), 
                        Text(progressText, style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade600)),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Material(
                    color: Colors.transparent, 
                    child: Ink(
                      decoration: BoxDecoration(color: isDark ? theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)), 
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16), 
                        onTap: () { 
                          Navigator.push(context, MaterialPageRoute(builder: (context) => FilteredCafeListScreen(title: "Visited Cafes", filterType: "visited", allCafes: allCafes, prefs: _prefs, userPosition: userPosition))).then((_) { 
                            _initPreferences().then((_) { processFiltersAndSorting(); }); 
                          }); 
                        }, 
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), 
                          child: Column(
                            children: [
                              const Icon(Icons.check_circle, size: 26, color: Colors.blueAccent), 
                              const SizedBox(height: 6), 
                              Text(validVisitedCafes.length.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)), 
                              const SizedBox(height: 2), 
                              Text("Visited", style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: Colors.grey.shade500))
                            ]
                          )
                        )
                      )
                    )
                  ),
                ),
              ),
              const SizedBox(width: 16),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(borderRadius: BorderRadius.circular(16), boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]),
                  child: Material(
                    color: Colors.transparent, 
                    child: Ink(
                      decoration: BoxDecoration(color: isDark ? theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)), 
                      child: InkWell(
                        borderRadius: BorderRadius.circular(16), 
                        onTap: () { 
                          Navigator.push(context, MaterialPageRoute(builder: (context) => FilteredCafeListScreen(title: "My Hitlist", filterType: "hitlist", allCafes: allCafes, prefs: _prefs, userPosition: userPosition))).then((_) { 
                            _initPreferences().then((_) { processFiltersAndSorting(); }); 
                          }); 
                        }, 
                        child: Padding(
                          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16), 
                          child: Column(
                            children: [
                              const Icon(Icons.favorite, size: 26, color: Colors.red), 
                              const SizedBox(height: 6), 
                              Text(validBookmarkedCafes.length.toString(), style: TextStyle(fontSize: 24, fontWeight: FontWeight.w900, color: theme.colorScheme.onSurface)), 
                              const SizedBox(height: 2), 
                              Text("Hitlist", style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold, color: Colors.grey.shade500, letterSpacing: 1.1))
                            ]
                          )
                        )
                      )
                    )
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 16),
          Container(
            decoration: BoxDecoration(borderRadius: BorderRadius.circular(12), boxShadow: [if (!isDark) BoxShadow(color: Colors.black.withValues(alpha: 0.03), blurRadius: 8, offset: const Offset(0, 2))]),
            child: Material(
              color: Colors.transparent,
              child: Ink(
                decoration: BoxDecoration(color: isDark ? theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                child: InkWell(
                  borderRadius: BorderRadius.circular(12),
                  onTap: () { 
                    Navigator.push(context, MaterialPageRoute(builder: (context) => PassportStampsScreen(
                      prefs: _prefs, 
                      allCafes: allCafes, 
                      onNavigateToCafe: (cafe) async { 
                        List<String> loadedNotes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                        await Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(
                          cafe: cafe, 
                          isBookmarked: bookmarkedCafes.contains(cafe.name), 
                          isVisited: visitedCafes.contains(cafe.name), 
                          initialNotes: loadedNotes, 
                          onBookmarkChanged: () => toggleBookmark(cafe.name), 
                          onVisitedChanged: (status) => toggleVisited(cafe.name, status), 
                          onNoteAdded: (text, isoDate) async { 
                            List<String> notes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                            notes.add(jsonEncode({'date': isoDate, 'text': text})); 
                            await _prefs.setStringList('notes_${cafe.name}', notes); 
                          }, 
                          onNoteDeleted: (index) async { 
                            List<String> notes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                            if (index >= 0 && index < notes.length) { 
                              notes.removeAt(index); 
                              await _prefs.setStringList('notes_${cafe.name}', notes); 
                            } 
                          }
                        ))); 
                        _initPreferences().then((_) { processFiltersAndSorting(); }); 
                      }
                    ))).then((_) { 
                      _initPreferences().then((_) { processFiltersAndSorting(); }); 
                    }); 
                  },
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 16),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Expanded(
                          child: Row(
                            children: [
                              const Icon(Icons.confirmation_num, size: 20, color: Colors.amber), 
                              const SizedBox(width: 10), 
                              Expanded(child: Text("Total Passport Stamps Collected", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13, color: theme.colorScheme.onSurface)))
                            ]
                          )
                        ),
                        const SizedBox(width: 16),
                        Row(
                          children: [
                            Text("$validTotalPassportStamps", style: TextStyle(fontWeight: FontWeight.w900, fontSize: 16, color: theme.colorScheme.onSurface)), 
                            const SizedBox(width: 8), 
                            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade500)
                          ]
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: 20),
          Text("Tools & Settings", style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)),
          const SizedBox(height: 10),
          Card(
            color: isDark ? theme.colorScheme.surface : Colors.white, 
            elevation: 0, 
            margin: EdgeInsets.zero, 
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16), side: BorderSide(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
            child: Column(
              children: [
                ListTile(
                  dense: true, 
                  visualDensity: VisualDensity.compact, 
                  leading: const Icon(Icons.push_pin, size: 22, color: Colors.teal), 
                  title: const Text("My Pin Notes", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                  subtitle: const Text("Read all your pinned tasting notes", style: TextStyle(fontSize: 12)), 
                  trailing: const Icon(Icons.chevron_right, size: 18), 
                  onTap: () { 
                    Navigator.push(context, MaterialPageRoute(builder: (context) => AllPinNotesScreen(
                      prefs: _prefs, 
                      allCafes: allCafes, 
                      onNavigateToCafe: (cafe) async { 
                        List<String> loadedNotes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                        await Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(
                          cafe: cafe, 
                          isBookmarked: bookmarkedCafes.contains(cafe.name), 
                          isVisited: visitedCafes.contains(cafe.name), 
                          initialNotes: loadedNotes, 
                          onBookmarkChanged: () => toggleBookmark(cafe.name), 
                          onVisitedChanged: (status) => toggleVisited(cafe.name, status), 
                          onNoteAdded: (text, isoDate) async { 
                            List<String> notes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                            notes.add(jsonEncode({'date': isoDate, 'text': text})); 
                            await _prefs.setStringList('notes_${cafe.name}', notes); 
                          }, 
                          onNoteDeleted: (index) async { 
                            List<String> notes = _prefs.getStringList('notes_${cafe.name}') ?? []; 
                            if (index >= 0 && index < notes.length) { 
                              notes.removeAt(index); 
                              await _prefs.setStringList('notes_${cafe.name}', notes); 
                            } 
                          }
                        ))); 
                        _initPreferences().then((_) { processFiltersAndSorting(); }); 
                      }
                    ))).then((_) { 
                      processFiltersAndSorting(); 
                    }); 
                  }
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true, 
                  visualDensity: VisualDensity.compact, 
                  leading: const Icon(Icons.share, size: 22, color: Colors.blueAccent), 
                  title: const Text("Share My Hitlist", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                  subtitle: const Text("Send your hitlist to a friend", style: TextStyle(fontSize: 12)), 
                  trailing: const Icon(Icons.chevron_right, size: 18), 
                  onTap: _shareMyHitlist
                ),
                const Divider(height: 1),
                ListTile(
                  dense: true, 
                  visualDensity: VisualDensity.compact, 
                  leading: const Icon(Icons.lightbulb_outline, size: 22, color: Colors.amber), 
                  title: const Text("Suggest & Feedback", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                  subtitle: const Text("Suggest cafes or request new features", style: TextStyle(fontSize: 12)), 
                  trailing: const Icon(Icons.chevron_right, size: 18), 
                  onTap: () { 
                    showModalBottomSheet(
                      context: context, 
                      isScrollControlled: true, 
                      backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
                      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))), 
                      builder: (context) => const SuggestionBottomSheet()
                    ); 
                  }
                ),
                const Divider(height: 1),
                if (_isDevMenuUnlocked) ...[
                  ListTile(
                    dense: true, 
                    visualDensity: VisualDensity.compact, 
                    leading: const Icon(Icons.developer_mode, size: 22, color: Colors.orange), 
                    title: const Text("Developer Mode", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                    subtitle: const Text("Bypass GPS and Time Locks", style: TextStyle(fontSize: 12)), 
                    trailing: Switch(
                      value: _isDevMode, 
                      activeThumbColor: Colors.orange, 
                      activeTrackColor: Colors.orange.withValues(alpha: 0.5), 
                      onChanged: (val) async { 
                        setState(() { 
                          _isDevMode = val; 
                          if (!val) { 
                            _isDevMenuUnlocked = false; 
                            _secretTapCount = 0; 
                          } 
                        }); 
                        await _prefs.setBool('dev_mode', val); 
                      }
                    )
                  ),
                  const Divider(height: 1),
                ],
                ListTile(
                  dense: true, 
                  visualDensity: VisualDensity.compact, 
                  leading: const Icon(Icons.info_outline, size: 22, color: Colors.grey), 
                  title: const Text("App Version", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14)), 
                  subtitle: const Text("Beta v1.1.27", style: TextStyle(fontSize: 12)),
                  onTap: () {
                    if (!_isDevMenuUnlocked) {
                      _secretTapCount++;
                      if (_secretTapCount == 3) { 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Tap 4 more times to unlock Developer Mode'), duration: Duration(seconds: 1))); 
                      } else if (_secretTapCount >= 7) { 
                        setState(() { _isDevMenuUnlocked = true; }); 
                        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('🛠️ Developer Mode Unlocked!'), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)); 
                      }
                    }
                  },
                ),
              ],
            ),
          )
        ],
      ),
    );
  }
}

// ============================================================================
// FILTERED CAFE LIST SCREEN
// ============================================================================
class FilteredCafeListScreen extends StatefulWidget {
  final String title;
  final String filterType; 
  final List<Cafe> allCafes;
  final SharedPreferences prefs;
  final Position? userPosition;

  const FilteredCafeListScreen({super.key, required this.title, required this.filterType, required this.allCafes, required this.prefs, this.userPosition});

  @override
  State<FilteredCafeListScreen> createState() => _FilteredCafeListScreenState();
}

class _FilteredCafeListScreenState extends State<FilteredCafeListScreen> {
  List<String> bookmarkedCafes = [];
  List<String> visitedCafes = [];
  late String _selectedSort; 
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = "";
  Position? _currentPosition;

  @override
  void initState() { 
    super.initState(); 
    _currentPosition = widget.userPosition; 
    _selectedSort = widget.filterType == 'visited' ? "Most Recent" : "A-Z";
    _loadPreferences(); 
  }

  void _loadPreferences() { 
    setState(() { 
      bookmarkedCafes = widget.prefs.getStringList('saved_bookmarks') ?? []; 
      visitedCafes = widget.prefs.getStringList('saved_visited') ?? []; 
    }); 
  }

  Future<void> _refreshLocation() async {
    bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
    if (!serviceEnabled) { return; }
    LocationPermission permission = await Geolocator.checkPermission();
    if (permission == LocationPermission.denied) { 
      permission = await Geolocator.requestPermission(); 
      if (permission == LocationPermission.denied) { return; } 
    }
    if (permission == LocationPermission.deniedForever) { return; }
    final position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high));
    if (mounted) { setState(() { _currentPosition = position; }); }
  }

  Future<void> toggleBookmark(String name) async {
    setState(() { 
      if (bookmarkedCafes.contains(name)) { bookmarkedCafes.remove(name); } 
      else { bookmarkedCafes.add(name); } 
    });
    await widget.prefs.setStringList('saved_bookmarks', bookmarkedCafes);
  }

  Future<void> toggleVisited(String name, bool status) async {
    setState(() {
      if (status) {
        if (!visitedCafes.contains(name)) { 
          visitedCafes.add(name); 
          List<String> stamps = widget.prefs.getStringList('visit_logs_$name') ?? []; 
          if (stamps.isEmpty) { 
            stamps.add(jsonEncode({'date': DateTime.now().toIso8601String()})); 
            widget.prefs.setStringList('visit_logs_$name', stamps); 
          } 
        }
      } else { 
        visitedCafes.remove(name); 
        widget.prefs.remove('visit_logs_$name'); 
      }
    });
    await widget.prefs.setStringList('saved_visited', visitedCafes);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final cardBgColor = isDark ? theme.colorScheme.surface : Colors.white;
    final Set<String> validNames = widget.allCafes.map((c) => c.name.trim()).toSet();

    List<Cafe> displayedCafes = widget.allCafes.where((cafe) {
      if (widget.filterType == 'visited') { return visitedCafes.contains(cafe.name) && validNames.contains(cafe.name.trim()); }
      else { return bookmarkedCafes.contains(cafe.name) && validNames.contains(cafe.name.trim()); }
    }).toList();

    if (_searchQuery.isNotEmpty) { 
      displayedCafes = displayedCafes.where((c) => c.name.toLowerCase().contains(_searchQuery.toLowerCase())).toList(); 
    }

    if (_selectedSort == "Most Recent" && widget.filterType == 'visited') {
      displayedCafes.sort((a, b) {
        DateTime? getLatestDate(Cafe c) {
          List<String> logs = widget.prefs.getStringList('visit_logs_${c.name}') ?? [];
          if (logs.isEmpty) { return null; }
          DateTime latest = DateTime.fromMillisecondsSinceEpoch(0);
          for (String log in logs) { 
            try { 
              DateTime d = DateTime.parse(jsonDecode(log)['date']); 
              if (d.isAfter(latest)) { latest = d; } 
            } catch (_) {} 
          }
          return latest;
        }
        DateTime? dateA = getLatestDate(a); 
        DateTime? dateB = getLatestDate(b);
        if (dateA == null && dateB == null) { return 0; }
        if (dateA == null) { return 1; } 
        if (dateB == null) { return -1; } 
        return dateB.compareTo(dateA); 
      });
    } else if (_selectedSort == "A-Z") { 
      displayedCafes.sort((a, b) => a.name.toLowerCase().compareTo(b.name.toLowerCase())); 
    } else if (_selectedSort == "Z-A") { 
      displayedCafes.sort((a, b) => b.name.toLowerCase().compareTo(a.name.toLowerCase())); 
    } else if (_selectedSort == "Nearest to Me" && _currentPosition != null) {
      displayedCafes.sort((a, b) => Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, a.latitude, a.longitude).compareTo(Geolocator.distanceBetween(_currentPosition!.latitude, _currentPosition!.longitude, b.latitude, b.longitude)));
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: Text(widget.title.toUpperCase(), style: const TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.0, fontSize: 16)), centerTitle: true),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16.0, vertical: 8.0),
            child: Row(
              children: [
                Expanded(
                  flex: 3,
                  child: SizedBox(
                    height: 40,
                    child: SearchBar(
                      controller: _searchController, 
                      hintText: 'Search...', 
                      hintStyle: WidgetStateProperty.all(const TextStyle(color: Colors.grey, fontSize: 13)), 
                      leading: Icon(Icons.search, color: isDark ? Colors.white70 : Colors.black87, size: 18),
                      trailing: [
                        if (_searchQuery.isNotEmpty) 
                          IconButton(
                            icon: const Icon(Icons.close, size: 16, color: Colors.grey), 
                            onPressed: () { 
                              _searchController.clear(); 
                              setState(() { _searchQuery = ""; }); 
                            }
                          )
                      ],
                      backgroundColor: WidgetStateProperty.all(isDark ? theme.colorScheme.surfaceContainerHigh : Colors.white), 
                      elevation: WidgetStateProperty.all(1), 
                      shape: WidgetStateProperty.all(RoundedRectangleBorder(borderRadius: BorderRadius.circular(8))),
                      onChanged: (value) { 
                        setState(() { _searchQuery = value; }); 
                      },
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  flex: 2,
                  child: Container(
                    height: 40, padding: const EdgeInsets.symmetric(horizontal: 10), 
                    decoration: BoxDecoration(color: cardBgColor, borderRadius: BorderRadius.circular(8), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _selectedSort, 
                        isExpanded: true, 
                        icon: Icon(Icons.sort, size: 16, color: isDark ? Colors.white70 : Colors.black87), 
                        style: TextStyle(color: theme.colorScheme.onSurface, fontSize: 12, fontWeight: FontWeight.w600), 
                        dropdownColor: cardBgColor,
                        items: [
                          if (widget.filterType == 'visited') 
                            const DropdownMenuItem(value: "Most Recent", child: Text("Sort: Recent")), 
                          const DropdownMenuItem(value: "A-Z", child: Text("Sort: A-Z")), 
                          const DropdownMenuItem(value: "Z-A", child: Text("Sort: Z-A")), 
                          const DropdownMenuItem(value: "Nearest to Me", child: Text("Sort: Nearest"))
                        ],
                        onChanged: (newValue) { 
                          if (newValue != null) { 
                            setState(() { _selectedSort = newValue; }); 
                            if (newValue == "Nearest to Me") { 
                              ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Updating live location...'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating)); 
                              _refreshLocation(); 
                            } 
                          } 
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          Expanded(
            child: displayedCafes.isEmpty
              ? Center(child: Text("No cafes found in your ${widget.title.toLowerCase()}.", style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)))
              : ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                  itemCount: displayedCafes.length, 
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemBuilder: (context, index) {
                    return CafeListTile(
                      cafe: displayedCafes[index], 
                      userPos: _currentPosition, 
                      isDark: isDark,
                      isFav: bookmarkedCafes.contains(displayedCafes[index].name), 
                      isVisited: visitedCafes.contains(displayedCafes[index].name),
                      onFav: () => toggleBookmark(displayedCafes[index].name),
                      onTap: () {
                        Navigator.push(context, MaterialPageRoute(builder: (context) => DetailScreen(
                          cafe: displayedCafes[index], 
                          isBookmarked: bookmarkedCafes.contains(displayedCafes[index].name), 
                          isVisited: visitedCafes.contains(displayedCafes[index].name),
                          initialNotes: widget.prefs.getStringList('notes_${displayedCafes[index].name}') ?? [],
                          onBookmarkChanged: () => toggleBookmark(displayedCafes[index].name),
                          onVisitedChanged: (status) => toggleVisited(displayedCafes[index].name, status),
                          onNoteAdded: (text, date) async { 
                            List<String> notes = widget.prefs.getStringList('notes_${displayedCafes[index].name}') ?? []; 
                            notes.add(jsonEncode({'date': date, 'text': text})); 
                            await widget.prefs.setStringList('notes_${displayedCafes[index].name}', notes); 
                          },
                          onNoteDeleted: (idx) async { 
                            List<String> notes = widget.prefs.getStringList('notes_${displayedCafes[index].name}') ?? []; 
                            if (idx >= 0 && idx < notes.length) { 
                              notes.removeAt(idx); 
                              await widget.prefs.setStringList('notes_${displayedCafes[index].name}', notes); 
                            } 
                          }
                        ))).then((_) { 
                          _loadPreferences(); 
                          setState((){}); 
                        });
                      },
                    );
                  },
                ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// SUGGESTION BOTTOM SHEET
// ============================================================================
class SuggestionBottomSheet extends StatefulWidget {
  const SuggestionBottomSheet({super.key});
  @override
  State<SuggestionBottomSheet> createState() => _SuggestionBottomSheetState();
}

class _SuggestionBottomSheetState extends State<SuggestionBottomSheet> {
  final TextEditingController field1Ctrl = TextEditingController();
  final TextEditingController field2Ctrl = TextEditingController();
  bool isSubmitting = false;
  String suggestionType = "Cafe Suggestion"; 

  @override
  void dispose() { 
    field1Ctrl.dispose(); 
    field2Ctrl.dispose(); 
    super.dispose(); 
  }

  @override
  Widget build(BuildContext context) {
    bool isFeedback = suggestionType == "App Feedback";
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min, 
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))), 
          const SizedBox(height: 24),
          
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16), 
            decoration: BoxDecoration(color: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.grey.shade200, borderRadius: BorderRadius.circular(12)),
            child: DropdownButtonHideUnderline(
              child: DropdownButton<String>(
                value: suggestionType, 
                isExpanded: true, 
                icon: const Icon(Icons.keyboard_arrow_down), 
                style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface), 
                dropdownColor: Theme.of(context).brightness == Brightness.dark ? const Color(0xFF2A2A2A) : Colors.white,
                items: const [
                  DropdownMenuItem(value: "Cafe Suggestion", child: Text("📍 Suggest a Cafe")), 
                  DropdownMenuItem(value: "App Feedback", child: Text("💡 App Feedback & Features"))
                ],
                onChanged: (val) { 
                  if (val != null) { 
                    setState(() { suggestionType = val; field1Ctrl.clear(); field2Ctrl.clear(); }); 
                  } 
                },
              ),
            ),
          ),
          const SizedBox(height: 20),
          
          Text(isFeedback ? "Help Us Brew a Better App ☕" : "Suggest a Cafe", style: const TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), 
          const SizedBox(height: 8),
          
          Text(isFeedback ? "Found a pesky bug or have a brilliant idea? Drop it here!" : "Know a hidden gem we should add? Send us the details.", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)), 
          const SizedBox(height: 24),
          
          TextField(
            controller: field1Ctrl, 
            style: const TextStyle(fontSize: 14), 
            decoration: InputDecoration(labelText: isFeedback ? "Subject" : "Cafe Name & Area", border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))
          ), 
          const SizedBox(height: 16),
          
          TextField(
            controller: field2Ctrl, 
            maxLines: 3, 
            style: const TextStyle(fontSize: 14), 
            decoration: InputDecoration(labelText: isFeedback ? "The Details..." : "Why should we add it?", alignLabelWithHint: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))
          ), 
          const SizedBox(height: 24),
          
          SizedBox(
            width: double.infinity,
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, padding: const EdgeInsets.symmetric(vertical: 14), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))),
              icon: isSubmitting ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(color: Colors.white, strokeWidth: 2)) : const Icon(Icons.send, size: 18),
              label: Text(isSubmitting ? "Sending..." : "Send ${isFeedback ? 'Feedback' : 'Suggestion'}", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
              onPressed: isSubmitting ? null : () async {
                if (field1Ctrl.text.trim().isEmpty) { return; }
                setState(() { isSubmitting = true; });
                try {
                  await http.post(Uri.parse("https://script.google.com/macros/s/AKfycbyOKAdoN85uo6Wh30TQSw64dNNL8ctNsiqnDY2ojNDCR9CheX27swYw-jF3ELMRld_Q/exec"), body: {"type": suggestionType, "subject": field1Ctrl.text.trim(), "details": field2Ctrl.text.trim()});
                  if (context.mounted) { 
                    Navigator.pop(context); 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Sent! Thank you."), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating)); 
                  }
                } catch (e) {
                  setState(() { isSubmitting = false; });
                  if (context.mounted) { 
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Failed to send."), backgroundColor: Colors.red, behavior: SnackBarBehavior.floating)); 
                  }
                }
              },
            ),
          ),
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// PASSPORT STAMPS SCREEN
// ============================================================================
class PassportStampsScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final List<Cafe> allCafes;
  final Future<void> Function(Cafe) onNavigateToCafe;
  
  const PassportStampsScreen({super.key, required this.prefs, required this.allCafes, required this.onNavigateToCafe});
  
  @override
  State<PassportStampsScreen> createState() => _PassportStampsScreenState();
}

class _PassportStampsScreenState extends State<PassportStampsScreen> {
  List<CafeStampGroup> _stampGroups = [];
  String _selectedSort = 'Most Recent';

  @override
  void initState() { 
    super.initState(); 
    _loadStamps(); 
  }

  void _loadStamps() {
    List<CafeStampGroup> temp = [];
    final Set<String> validNames = widget.allCafes.map((c) => c.name.trim()).toSet();
    for (String key in widget.prefs.getKeys()) {
      if (key.startsWith('visit_logs_')) {
        String cafeName = key.replaceFirst('visit_logs_', '').trim();
        if (!validNames.contains(cafeName)) { continue; }
        List<String> logs = widget.prefs.getStringList(key) ?? [];
        if (logs.isNotEmpty) {
          List<DateTime> dates = [];
          for (String log in logs) { 
            try { 
              dates.add(DateTime.parse(jsonDecode(log)['date'])); 
            } catch (e) { /* ignore */ } 
          }
          dates.sort((a, b) => b.compareTo(a));
          temp.add(CafeStampGroup(cafeName, dates));
        }
      }
    }
    _stampGroups = temp;
    _sortGroups();
  }

  void _sortGroups() {
    if (_selectedSort == 'Most Recent') { 
      _stampGroups.sort((a, b) => b.stampDates.first.compareTo(a.stampDates.first)); 
    } else if (_selectedSort == 'A-Z') { 
      _stampGroups.sort((a, b) => a.cafeName.toLowerCase().compareTo(b.cafeName.toLowerCase())); 
    } else if (_selectedSort == 'Z-A') { 
      _stampGroups.sort((a, b) => b.cafeName.toLowerCase().compareTo(a.cafeName.toLowerCase())); 
    }
    setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('PASSPORT STAMPS', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.0, fontSize: 16)), centerTitle: true),
      body: _stampGroups.isEmpty
          ? Center(child: Text("You haven't stamped any passports yet.", style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_stampGroups.length} Cafes Visited', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSort, 
                          icon: Icon(Icons.sort, size: 16, color: isDark ? Colors.blue.shade300 : Colors.blueAccent), 
                          style: TextStyle(color: isDark ? Colors.blue.shade300 : Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold), 
                          dropdownColor: isDark ? theme.colorScheme.surface : Colors.white,
                          items: const [
                            DropdownMenuItem(value: "Most Recent", child: Text("Most Recent")), 
                            DropdownMenuItem(value: "A-Z", child: Text("A-Z")), 
                            DropdownMenuItem(value: "Z-A", child: Text("Z-A"))
                          ],
                          onChanged: (val) { 
                            if (val != null) { 
                              setState(() { _selectedSort = val; _sortGroups(); }); 
                            } 
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                    itemCount: _stampGroups.length,
                    itemBuilder: (context, index) {
                      final group = _stampGroups[index];
                      final targetCafe = widget.allCafes.cast<Cafe?>().firstWhere((c) => c?.name.trim() == group.cafeName, orElse: () => null);
                      return _ExpandableStampCard(group: group, cafe: targetCafe, theme: theme, isDark: isDark, onNavigate: widget.onNavigateToCafe, onRefresh: _loadStamps);
                    },
                  ),
                ),
              ],
            ),
    );
  }
}

class _ExpandableStampCard extends StatefulWidget {
  final CafeStampGroup group;
  final Cafe? cafe;
  final ThemeData theme;
  final bool isDark;
  final Future<void> Function(Cafe) onNavigate;
  final VoidCallback onRefresh; 

  const _ExpandableStampCard({required this.group, this.cafe, required this.theme, required this.isDark, required this.onNavigate, required this.onRefresh});
  
  @override
  State<_ExpandableStampCard> createState() => _ExpandableStampCardState();
}

class _ExpandableStampCardState extends State<_ExpandableStampCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(color: widget.isDark ? widget.theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.isDark ? widget.theme.dividerColor : Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16), 
            onTap: () { 
              setState(() { _isExpanded = !_isExpanded; }); 
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey), 
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start, 
                      children: [
                        Text(widget.group.cafeName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis), 
                        const SizedBox(height: 4), 
                        Text("${widget.group.stampDates.length} Stamp${widget.group.stampDates.length > 1 ? 's' : ''}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500))
                      ]
                    )
                  ),
                  if (widget.cafe != null) 
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0), 
                      child: IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20, color: Colors.blueAccent), 
                        padding: EdgeInsets.zero, 
                        constraints: const BoxConstraints(), 
                        tooltip: 'Open Cafe Card', 
                        onPressed: () async { 
                          await widget.onNavigate(widget.cafe!); 
                          widget.onRefresh(); 
                        }
                      )
                    )
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300), 
            curve: Curves.easeInOut,
            child: !_isExpanded ? const SizedBox.shrink() : Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: widget.isDark ? widget.theme.dividerColor : Colors.grey.shade200, height: 1), 
                  const SizedBox(height: 16),
                  ...widget.group.stampDates.asMap().entries.map((entry) {
                    return Padding(
                      padding: EdgeInsets.only(bottom: entry.key == widget.group.stampDates.length - 1 ? 0 : 12.0),
                      child: Row(
                        children: [
                          const Icon(Icons.stars_outlined, size: 16, color: Colors.amber), 
                          const SizedBox(width: 12), 
                          Text(formatStampTimestamp(entry.value.toIso8601String()), style: TextStyle(fontSize: 14, color: widget.theme.colorScheme.onSurface, fontWeight: FontWeight.w500))
                        ]
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// ALL PIN NOTES SCREEN
// ============================================================================
class AllPinNotesScreen extends StatefulWidget {
  final SharedPreferences prefs;
  final List<Cafe> allCafes;
  final Future<void> Function(Cafe) onNavigateToCafe;

  const AllPinNotesScreen({super.key, required this.prefs, required this.allCafes, required this.onNavigateToCafe});
  
  @override
  State<AllPinNotesScreen> createState() => _AllPinNotesScreenState();
}

class _AllPinNotesScreenState extends State<AllPinNotesScreen> {
  List<CafePinNotesGroup> _groupedEntries = [];
  String _selectedSort = "Most Recent"; 

  @override
  void initState() { 
    super.initState(); 
    _loadEntries(); 
  }

  void _sortGroups() {
    if (_selectedSort == "Most Recent") { 
      _groupedEntries.sort((a, b) => b.entries.first.date.compareTo(a.entries.first.date)); 
    } else if (_selectedSort == "A-Z") { 
      _groupedEntries.sort((a, b) => a.cafeName.toLowerCase().compareTo(b.cafeName.toLowerCase())); 
    } else if (_selectedSort == "Z-A") { 
      _groupedEntries.sort((a, b) => b.cafeName.toLowerCase().compareTo(a.cafeName.toLowerCase())); 
    }
  }

  void _loadEntries() {
    List<CafePinNotesGroup> tempGroups = [];
    final Set<String> validNames = widget.allCafes.map((c) => c.name.trim()).toSet();
    for (String key in widget.prefs.getKeys()) {
      if (key.startsWith('notes_')) {
        String cafeName = key.replaceFirst('notes_', '').trim();
        if (!validNames.contains(cafeName)) { continue; }
        List<String> notes = widget.prefs.getStringList(key) ?? [];
        List<PinNoteEntry> cafeEntries = [];
        for (int i = 0; i < notes.length; i++) {
          try { 
            final data = jsonDecode(notes[i]); 
            cafeEntries.add(PinNoteEntry(DateTime.parse(data['date']), data['text'], i)); 
          } catch (e) { /* ignore */ }
        }
        if (cafeEntries.isNotEmpty) { 
          cafeEntries.sort((a, b) => b.date.compareTo(a.date)); 
          tempGroups.add(CafePinNotesGroup(cafeName, cafeEntries)); 
        }
      }
    }
    _groupedEntries = tempGroups;
    _sortGroups(); 
    setState(() {});
  }

  Future<void> _deletePinNote(String cafeName, int index) async {
    List<String> notes = widget.prefs.getStringList('notes_$cafeName') ?? [];
    if (index >= 0 && index < notes.length) { 
      notes.removeAt(index); 
      await widget.prefs.setStringList('notes_$cafeName', notes); 
      _loadEntries(); 
    }
  }

  Future<void> _addGlobalQuickNote(String cafeName, String text, String isoDate) async {
    List<String> notes = widget.prefs.getStringList('notes_$cafeName') ?? [];
    notes.add(jsonEncode({'date': isoDate, 'text': text})); 
    notes.sort((a, b) { 
      try { return DateTime.parse(jsonDecode(b)['date']).compareTo(DateTime.parse(jsonDecode(a)['date'])); } catch (_) { return 0; } 
    });
    await widget.prefs.setStringList('notes_$cafeName', notes);
    _loadEntries(); 
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(title: const Text('ALL PIN NOTES', style: TextStyle(fontWeight: FontWeight.w900, letterSpacing: 2.0, fontSize: 16)), centerTitle: true),
      body: _groupedEntries.isEmpty
          ? Center(child: Text("You haven't written any notes yet.", style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic)))
          : Column(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text('${_groupedEntries.length} Cafes Documented', style: TextStyle(color: isDark ? Colors.white70 : Colors.black54, fontSize: 13, fontWeight: FontWeight.bold)),
                      DropdownButtonHideUnderline(
                        child: DropdownButton<String>(
                          value: _selectedSort, 
                          icon: Icon(Icons.sort, size: 16, color: isDark ? Colors.blue.shade300 : Colors.blueAccent), 
                          style: TextStyle(color: isDark ? Colors.blue.shade300 : Colors.blueAccent, fontSize: 13, fontWeight: FontWeight.bold), 
                          dropdownColor: isDark ? theme.colorScheme.surface : Colors.white,
                          items: const [
                            DropdownMenuItem(value: "Most Recent", child: Text("Most Recent")), 
                            DropdownMenuItem(value: "A-Z", child: Text("A-Z")), 
                            DropdownMenuItem(value: "Z-A", child: Text("Z-A"))
                          ],
                          onChanged: (val) { 
                            if (val != null) { 
                              setState(() { _selectedSort = val; _sortGroups(); }); 
                            } 
                          },
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: ListView.builder(
                    padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8), 
                    itemCount: _groupedEntries.length,
                    itemBuilder: (context, index) {
                      final group = _groupedEntries[index];
                      final targetCafe = widget.allCafes.cast<Cafe?>().firstWhere((c) => c?.name.trim() == group.cafeName, orElse: () => null);
                      return _ExpandableCafeCard(group: group, cafe: targetCafe, theme: theme, isDark: isDark, onNavigate: widget.onNavigateToCafe, onRefresh: _loadEntries, onDeleteNote: _deletePinNote);
                    },
                  ),
                ),
              ],
            ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          showModalBottomSheet(
            context: context, 
            isScrollControlled: true, 
            backgroundColor: theme.scaffoldBackgroundColor, 
            shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
            builder: (context) => QuickNoteBottomSheet(allCafes: widget.allCafes, onSave: _addGlobalQuickNote),
          );
        },
        icon: const Icon(Icons.add), 
        label: const Text("Quick Note", style: TextStyle(fontWeight: FontWeight.bold)), 
        backgroundColor: Colors.blueAccent, 
        foregroundColor: Colors.white,
      ),
    );
  }
}

class _ExpandableCafeCard extends StatefulWidget {
  final CafePinNotesGroup group;
  final Cafe? cafe;
  final ThemeData theme;
  final bool isDark;
  final Future<void> Function(Cafe) onNavigate;
  final VoidCallback onRefresh;
  final Future<void> Function(String, int) onDeleteNote; 

  const _ExpandableCafeCard({required this.group, this.cafe, required this.theme, required this.isDark, required this.onNavigate, required this.onRefresh, required this.onDeleteNote});
  
  @override
  State<_ExpandableCafeCard> createState() => _ExpandableCafeCardState();
}

class _ExpandableCafeCardState extends State<_ExpandableCafeCard> {
  bool _isExpanded = false;

  @override
  Widget build(BuildContext context) {
    Map<String, List<PinNoteEntry>> localGroupedNotes = {};
    for (var entry in widget.group.entries) {
      String dateKey = formatNoteDate(entry.date);
      if (!localGroupedNotes.containsKey(dateKey)) { localGroupedNotes[dateKey] = []; }
      localGroupedNotes[dateKey]!.add(entry);
    }

    return Container(
      margin: const EdgeInsets.only(bottom: 12), 
      decoration: BoxDecoration(color: widget.isDark ? widget.theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: widget.isDark ? widget.theme.dividerColor : Colors.grey.shade300)),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          InkWell(
            borderRadius: BorderRadius.circular(16), 
            onTap: () { 
              setState(() { _isExpanded = !_isExpanded; }); 
            },
            child: Padding(
              padding: const EdgeInsets.all(16),
              child: Row(
                children: [
                  Icon(_isExpanded ? Icons.keyboard_arrow_up : Icons.keyboard_arrow_down, color: Colors.grey), 
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Expanded(child: Text(widget.group.cafeName, style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: widget.theme.colorScheme.onSurface), maxLines: 1, overflow: TextOverflow.ellipsis)),
                            const SizedBox(width: 8), 
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2), 
                              decoration: BoxDecoration(color: widget.isDark ? Colors.grey.shade800 : Colors.grey.shade200, borderRadius: BorderRadius.circular(6)), 
                              child: Text(formatNoteDate(widget.group.entries.first.date), style: TextStyle(fontSize: 10, fontWeight: FontWeight.bold, color: widget.isDark ? Colors.white70 : Colors.black54))
                            ),
                          ],
                        ),
                        const SizedBox(height: 4), 
                        Text("${widget.group.entries.length} Note${widget.group.entries.length > 1 ? 's' : ''}", style: TextStyle(fontSize: 12, fontWeight: FontWeight.w600, color: Colors.grey.shade500)),
                      ],
                    ),
                  ),
                  if (widget.cafe != null) 
                    Padding(
                      padding: const EdgeInsets.only(left: 8.0), 
                      child: IconButton(
                        icon: const Icon(Icons.open_in_new, size: 20, color: Colors.blueAccent), 
                        padding: EdgeInsets.zero, 
                        constraints: const BoxConstraints(), 
                        tooltip: 'Open Cafe Card', 
                        onPressed: () async { 
                          await widget.onNavigate(widget.cafe!); 
                          widget.onRefresh(); 
                        }
                      )
                    )
                ],
              ),
            ),
          ),
          AnimatedSize(
            duration: const Duration(milliseconds: 300), 
            curve: Curves.easeInOut,
            child: !_isExpanded ? const SizedBox.shrink() : Padding(
              padding: const EdgeInsets.only(left: 16, right: 16, bottom: 16),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Divider(color: widget.isDark ? widget.theme.dividerColor : Colors.grey.shade200, height: 1), 
                  const SizedBox(height: 16),
                  ...localGroupedNotes.keys.map((dateKey) {
                    var dayNotes = localGroupedNotes[dateKey]!;
                    return Padding(
                      padding: const EdgeInsets.only(bottom: 16.0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(children: [const Icon(Icons.calendar_today, size: 14, color: Colors.blueAccent), const SizedBox(width: 6), Text(dateKey, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent))]),
                          const SizedBox(height: 12),
                          ...dayNotes.asMap().entries.map((entryPair) {
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                if (entryPair.key > 0) 
                                  Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: widget.isDark ? widget.theme.dividerColor : Colors.grey.shade200)),
                                Row(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Expanded(child: Text(entryPair.value.text, style: TextStyle(fontSize: 14, color: widget.theme.colorScheme.onSurface, height: 1.4))), 
                                    const SizedBox(width: 12), 
                                    GestureDetector(
                                      onTap: () { 
                                        widget.onDeleteNote(widget.group.cafeName, entryPair.value.originalIndex); 
                                      }, 
                                      child: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade400)
                                    ),
                                  ],
                                ),
                              ],
                            );
                          }),
                        ],
                      ),
                    );
                  }),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// ============================================================================
// QUICK NOTE BOTTOM SHEET
// ============================================================================
class QuickNoteBottomSheet extends StatefulWidget {
  final List<Cafe> allCafes;
  final Future<void> Function(String cafeName, String text, String isoDate) onSave;

  const QuickNoteBottomSheet({super.key, required this.allCafes, required this.onSave});
  
  @override
  State<QuickNoteBottomSheet> createState() => _QuickNoteBottomSheetState();
}

class _QuickNoteBottomSheetState extends State<QuickNoteBottomSheet> {
  final TextEditingController _noteController = TextEditingController();
  final FocusNode _noteFocusNode = FocusNode(); 
  DateTime _selectedNoteDate = DateTime.now();
  Cafe? _selectedCafe;

  @override
  void dispose() { 
    _noteController.dispose(); 
    _noteFocusNode.dispose(); 
    super.dispose(); 
  }

  Future<void> _pickDate(BuildContext context) async {
    FocusManager.instance.primaryFocus?.unfocus();
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: _selectedNoteDate, 
      firstDate: DateTime(2020), 
      lastDate: DateTime.now(), 
      builder: (context, child) { 
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark 
              ? const ColorScheme.dark(primary: Colors.blueAccent, surface: Color(0xFF2A2A2A)) 
              : const ColorScheme.light(primary: Colors.black, surface: Colors.white)
          ), 
          child: child!
        ); 
      },
    );
    if (picked != null && picked != _selectedNoteDate) { 
      setState(() { _selectedNoteDate = picked; }); 
      _noteFocusNode.requestFocus(); 
    }
  }

  void _handleSave() {
    if (_selectedCafe == null) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Please select a cafe first."), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating)); 
      return; 
    }
    if (_noteController.text.trim().isEmpty) { 
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("⚠️ Please write a note before saving."), backgroundColor: Colors.orange, behavior: SnackBarBehavior.floating)); 
      return; 
    }
    final now = DateTime.now();
    final isoDateString = DateTime(_selectedNoteDate.year, _selectedNoteDate.month, _selectedNoteDate.day, now.hour, now.minute, now.second).toIso8601String();
    widget.onSave(_selectedCafe!.name, _noteController.text.trim(), isoDateString);
    Navigator.pop(context);
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text("✅ Quick Note saved!"), backgroundColor: Colors.green, behavior: SnackBarBehavior.floating));
  }

  @override
  Widget build(BuildContext context) {
    final isDark = Theme.of(context).brightness == Brightness.dark;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom, left: 20, right: 20, top: 16),
      child: Column(
        mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(child: Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2)))), 
          const SizedBox(height: 24),
          const Text("Quick Note", style: TextStyle(fontSize: 20, fontWeight: FontWeight.w900)), 
          const SizedBox(height: 4), 
          Text("Log a tasting note globally without leaving this screen.", style: TextStyle(fontSize: 13, color: Colors.grey.shade600)), 
          const SizedBox(height: 24),
          
          Autocomplete<Cafe>(
            displayStringForOption: (Cafe option) => option.name,
            optionsBuilder: (TextEditingValue val) { 
              if (val.text.isEmpty) { return widget.allCafes; } 
              return widget.allCafes.where((c) => c.name.toLowerCase().contains(val.text.toLowerCase())); 
            },
            onSelected: (Cafe selection) { 
              setState(() { _selectedCafe = selection; }); 
              FocusManager.instance.primaryFocus?.unfocus(); 
            },
            fieldViewBuilder: (c, ctrl, focusNode, onEditingComplete) { 
              return TextField(
                controller: ctrl, 
                focusNode: focusNode, 
                style: const TextStyle(fontSize: 14), 
                onChanged: (val) { setState(() { _selectedCafe = null; }); }, 
                decoration: InputDecoration(labelText: "Search for a Cafe...", prefixIcon: const Icon(Icons.search, size: 18), border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))
              ); 
            },
            optionsViewBuilder: (c, onSelected, options) { 
              return Align(
                alignment: Alignment.topLeft, 
                child: Material(
                  elevation: 4.0, 
                  color: isDark ? const Color(0xFF2A2A2A) : Colors.white, 
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)), 
                  child: ConstrainedBox(
                    constraints: BoxConstraints(maxHeight: 200, maxWidth: MediaQuery.of(context).size.width - 40), 
                    child: ListView.builder(
                      padding: EdgeInsets.zero, 
                      shrinkWrap: true, 
                      itemCount: options.length, 
                      itemBuilder: (c, i) { 
                        final option = options.elementAt(i); 
                        return InkWell(
                          onTap: () => onSelected(option), 
                          child: Padding(
                            padding: const EdgeInsets.all(16.0), 
                            child: Text(option.name, style: TextStyle(color: Theme.of(context).colorScheme.onSurface, fontWeight: FontWeight.bold))
                          )
                        ); 
                      }
                    )
                  )
                )
              ); 
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerLeft,
            child: InkWell(
              onTap: () => _pickDate(context), borderRadius: BorderRadius.circular(20),
              child: Container(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), 
                margin: const EdgeInsets.only(bottom: 8), 
                decoration: BoxDecoration(color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200, borderRadius: BorderRadius.circular(20)), 
                child: Row(
                  mainAxisSize: MainAxisSize.min, 
                  children: [
                    Icon(Icons.calendar_today, size: 14, color: isDark ? Colors.white70 : Colors.black87), 
                    const SizedBox(width: 6), 
                    Text(getDisplayDateForPill(_selectedNoteDate), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)), 
                    const SizedBox(width: 2), 
                    Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white54 : Colors.black54)
                  ]
                )
              ),
            ),
          ),
          TextField(
            controller: _noteController, 
            focusNode: _noteFocusNode, 
            maxLines: 3, 
            style: const TextStyle(fontSize: 14), 
            decoration: InputDecoration(labelText: "Your tasting notes...", alignLabelWithHint: true, border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)))
          ), 
          const SizedBox(height: 24),
          SizedBox(
            width: double.infinity, 
            child: ElevatedButton.icon(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.blueAccent, 
                foregroundColor: Colors.white, 
                padding: const EdgeInsets.symmetric(vertical: 14), 
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))
              ), 
              icon: const Icon(Icons.push_pin, size: 18), 
              label: const Text("Save Global Note", style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16)), 
              onPressed: _handleSave
            )
          ), 
          const SizedBox(height: 24),
        ],
      ),
    );
  }
}

// ============================================================================
// CAFE DETAIL SCREEN
// ============================================================================
class DetailScreen extends StatefulWidget {
  final Cafe cafe;
  final bool isBookmarked;
  final bool isVisited;
  final List<String> initialNotes;
  final VoidCallback onBookmarkChanged;
  final Function(bool) onVisitedChanged;
  final Function(String, String) onNoteAdded;
  final Function(int) onNoteDeleted;

  const DetailScreen({super.key, required this.cafe, required this.isBookmarked, required this.isVisited, required this.initialNotes, required this.onBookmarkChanged, required this.onVisitedChanged, required this.onNoteAdded, required this.onNoteDeleted});

  @override
  State<DetailScreen> createState() => _DetailScreenState();
}

class _DetailScreenState extends State<DetailScreen> {
  late bool _isBookmarked;
  late bool _isVisited;
  late List<String> _notes;
  final TextEditingController _noteController = TextEditingController();
  DateTime _selectedNoteDate = DateTime.now();
  List<String> _stampLogs = [];
  late SharedPreferences _localPrefs;

  @override
  void initState() {
    super.initState();
    _isBookmarked = widget.isBookmarked;
    _isVisited = widget.isVisited;
    _notes = List.from(widget.initialNotes);
    _sortNotes();
    _loadStampLogs();
  }

  Future<void> _loadStampLogs() async {
    _localPrefs = await SharedPreferences.getInstance();
    List<String> existingStamps = _localPrefs.getStringList('visit_logs_${widget.cafe.name}') ?? [];
    if (existingStamps.isEmpty && _isVisited) { 
      existingStamps.add(jsonEncode({'date': DateTime.now().toIso8601String()})); 
      await _localPrefs.setStringList('visit_logs_${widget.cafe.name}', existingStamps); 
    }
    setState(() { _stampLogs = existingStamps; });
  }

  Future<void> _addPassportStamp() async {
    bool isDevMode = _localPrefs.getBool('dev_mode') ?? false;
    if (!isDevMode && _stampLogs.isNotEmpty) {
      try {
        final lastStampDate = DateTime.parse(jsonDecode(_stampLogs.first)['date']);
        final difference = DateTime.now().difference(lastStampDate);
        if (difference.inHours < 5) {
          final hoursLeft = 4 - difference.inHours; 
          final minutesLeft = 60 - (difference.inMinutes % 60);
          if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('⏳ You recently stamped here! Try again in ${hoursLeft > 0 ? "$hoursLeft hr " : ""}$minutesLeft min.'), backgroundColor: Colors.orange.shade800, behavior: SnackBarBehavior.floating)); }
          return; 
        }
      } catch (e) { /* ignore */ }
    }
    if (!isDevMode) {
      bool serviceEnabled = await Geolocator.isLocationServiceEnabled();
      if (!serviceEnabled) { if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Please enable GPS to stamp your passport.'))); } return; }
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) { 
        permission = await Geolocator.requestPermission(); 
        if (permission == LocationPermission.denied) { return; } 
      }
      if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Verifying location...'), duration: Duration(seconds: 1), behavior: SnackBarBehavior.floating)); }
      Position position;
      try { 
        position = await Geolocator.getCurrentPosition(locationSettings: const LocationSettings(accuracy: LocationAccuracy.high)); 
      } catch (e) { 
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('⚠️ Could not verify your live location.'))); } 
        return; 
      }
      final distance = Geolocator.distanceBetween(position.latitude, position.longitude, widget.cafe.latitude, widget.cafe.longitude);
      if (distance > 200) { 
        if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text('📍 Too far away! You are ${(distance / 1000).toStringAsFixed(1)}km from the cafe.'), backgroundColor: Colors.red.shade800, behavior: SnackBarBehavior.floating)); } 
        return; 
      }
    }
    final logPayload = jsonEncode({'date': DateTime.now().toIso8601String()});
    setState(() { 
      _stampLogs.insert(0, logPayload); 
      if (!_isVisited) { 
        _isVisited = true; 
        widget.onVisitedChanged(true); 
      } 
    });
    await _localPrefs.setStringList('visit_logs_${widget.cafe.name}', _stampLogs);
    if (mounted) { ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(isDevMode ? '🛠️ Dev Mode: Stamped Successfully!' : '⚡ Passport Stamped Successfully!'), backgroundColor: isDevMode ? Colors.orange.shade800 : Colors.green, duration: const Duration(seconds: 2), behavior: SnackBarBehavior.floating)); }
  }

  Future<void> _deletePassportStamp(int targetIndex) async {
    setState(() { 
      _stampLogs.removeAt(targetIndex); 
      if (_stampLogs.isEmpty) { 
        _isVisited = false; 
        widget.onVisitedChanged(false); 
      } 
    });
    await _localPrefs.setStringList('visit_logs_${widget.cafe.name}', _stampLogs);
  }

  void _sortNotes() { 
    _notes.sort((a, b) { 
      try { return DateTime.parse(jsonDecode(b)['date']).compareTo(DateTime.parse(jsonDecode(a)['date'])); } 
      catch (e) { return 0; } 
    }); 
  }

  Future<void> _pickDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context, 
      initialDate: _selectedNoteDate, 
      firstDate: DateTime(2020), 
      lastDate: DateTime.now(), 
      builder: (context, child) { 
        return Theme(
          data: Theme.of(context).copyWith(
            colorScheme: Theme.of(context).brightness == Brightness.dark 
              ? const ColorScheme.dark(primary: Colors.blueAccent, surface: Color(0xFF2A2A2A)) 
              : const ColorScheme.light(primary: Colors.black, surface: Colors.white)
          ), 
          child: child!
        ); 
      },
    );
    if (picked != null && picked != _selectedNoteDate) { 
      setState(() { _selectedNoteDate = picked; }); 
    }
  }

  void _handleAddNote() {
    final text = _noteController.text.trim();
    if (text.isEmpty) { return; }
    final now = DateTime.now();
    final isoDateString = DateTime(_selectedNoteDate.year, _selectedNoteDate.month, _selectedNoteDate.day, now.hour, now.minute, now.second).toIso8601String();
    setState(() { 
      _notes.add(jsonEncode({'date': isoDateString, 'text': text})); 
      _sortNotes(); 
      _noteController.clear(); 
      _selectedNoteDate = DateTime.now(); 
    });
    widget.onNoteAdded(text, isoDateString);
  }

  Future<void> _makeCall() async {
    final String parsedNumber = widget.cafe.phone.trim().toUpperCase();
    if (parsedNumber == 'NA' || parsedNumber == 'N/A') { return; }
    // ignore: deprecated_member_use
    if (!await launchUrl(Uri.parse('tel:${parsedNumber.replaceAll(RegExp(r'[^\d+]'), '')}'))) { debugPrint('Could not launch dialer.'); }
  }

  Future<void> _openInstagram() async {
    if (!await launchUrl(Uri.parse(widget.cafe.instagramUrl), mode: LaunchMode.externalApplication)) { debugPrint('Could not open Instagram.'); }
  }

  String getInstagramHandle(String url) {
    try {
      Uri uri = Uri.parse(url);
      if (uri.pathSegments.isNotEmpty) {
        String firstSegment = uri.pathSegments.first;
        if (firstSegment == 'p' || firstSegment == 'reel') { return 'View Instagram Post'; }
        return '@$firstSegment';
      }
    } catch (_) { /* ignore */ }
    return 'Instagram Profile';
  }

  Future<void> _showNavigationOptions() async {
    try {
      final availableMaps = await MapLauncher.installedMaps;
      if (!mounted) { return; }
      bool isDark = Theme.of(context).brightness == Brightness.dark;
      showModalBottomSheet(
        context: context, 
        backgroundColor: Theme.of(context).scaffoldBackgroundColor, 
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
        builder: (context) { 
          return SafeArea(
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 16.0), 
              child: Column(
                mainAxisSize: MainAxisSize.min, 
                children: [
                  Container(width: 40, height: 4, decoration: BoxDecoration(color: Colors.grey.shade400, borderRadius: BorderRadius.circular(2))), 
                  const SizedBox(height: 16), 
                  Text('Navigate to ${widget.cafe.name}', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.onSurface)), 
                  const SizedBox(height: 16), 
                  ...availableMaps.map((map) {
                    bool isGoogle = map.mapName.toLowerCase() == 'google maps';
                    return ListTile(
                      leading: Container(
                        height: 46, width: 46, padding: const EdgeInsets.all(8),
                        decoration: BoxDecoration(color: isDark ? Colors.white.withValues(alpha: 0.05) : Colors.black.withValues(alpha: 0.03), borderRadius: BorderRadius.circular(14)),
                        child: Center(child: SvgPicture.asset(map.icon, package: 'map_launcher')),
                      ),
                      title: Text(map.mapName, style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.onSurface)), 
                      onTap: () async { 
                        Navigator.pop(context); 
                        if (isGoogle) { 
                          launchUrl(Uri.parse(widget.cafe.mapDirectionsUrl), mode: LaunchMode.externalApplication); 
                        } else {
                          String mapName = map.mapName.toLowerCase();
                          String searchQuery = Uri.encodeComponent('${widget.cafe.name} ${widget.cafe.address}');
                          if (mapName == 'waze') {
                            Uri wazeUri = Uri.parse('waze://?q=$searchQuery');
                            if (await canLaunchUrl(wazeUri)) { await launchUrl(wazeUri, mode: LaunchMode.externalApplication); return; }
                          } else if (mapName == 'apple maps') {
                            Uri appleUri = Uri.parse('http://maps.apple.com/?q=$searchQuery');
                            if (await canLaunchUrl(appleUri)) { await launchUrl(appleUri, mode: LaunchMode.externalApplication); return; }
                          } else if (mapName == 'amap' || mapName == 'gaode maps') {
                            Uri amapUri = Platform.isAndroid ? Uri.parse('androidamap://poi?sourceApplication=BlackPin&keywords=$searchQuery') : Uri.parse('iosamap://poi?sourceApplication=BlackPin&name=$searchQuery');
                            if (await canLaunchUrl(amapUri)) { await launchUrl(amapUri, mode: LaunchMode.externalApplication); return; }
                          }
                          map.showMarker(coords: Coords(widget.cafe.latitude, widget.cafe.longitude), title: widget.cafe.name, description: widget.cafe.address); 
                        }
                      }
                    );
                  }), 
                  const SizedBox(height: 8)
                ]
              )
            )
          ); 
        },
      );
    } catch (e) { 
      await launchUrl(Uri.parse(widget.cafe.mapDirectionsUrl), mode: LaunchMode.externalApplication); 
    }
  }

  void _shareCafeDetails() {
    // ignore: deprecated_member_use
    Share.share("Let's grab coffee at ${widget.cafe.name}! ☕\n\n📍 ${widget.cafe.address}\n🗺️ Directions: ${widget.cafe.mapDirectionsUrl}\n\n---\n📍 Pinned via BLACKPIN\nFind your black coffee.\n");
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    final iconColor = isDark ? Colors.white70 : Colors.black87;
    final String parsedNumber = widget.cafe.phone.trim().toUpperCase();
    final bool hasPhone = parsedNumber != 'NA' && parsedNumber != 'N/A';
    final currentDayStr = ['Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday', 'Sunday'][DateTime.now().weekday - 1];

    Map<String, List<Map<String, dynamic>>> localGroupedNotes = {};
    for (int i = 0; i < _notes.length; i++) {
      String noteDate = "Unknown Date"; String noteText = _notes[i];
      try {
        final Map<String, dynamic> data = jsonDecode(_notes[i]);
        final dateParsed = DateTime.parse(data['date'] ?? '');
        noteDate = '${['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'][dateParsed.month - 1]} ${dateParsed.day}, ${dateParsed.year}';
        noteText = data['text'] ?? '';
      } catch (_) { /* ignore */ }
      if (!localGroupedNotes.containsKey(noteDate)) { localGroupedNotes[noteDate] = []; }
      localGroupedNotes[noteDate]!.add({'originalIndex': i, 'text': noteText});
    }

    return Scaffold(
      backgroundColor: theme.scaffoldBackgroundColor,
      appBar: AppBar(
        title: Text(widget.cafe.name), centerTitle: true,
        actions: [
          IconButton(icon: const Icon(Icons.share, color: Colors.white), tooltip: 'Share Cafe', onPressed: _shareCafeDetails),
          IconButton(icon: Icon(_isBookmarked ? Icons.favorite : Icons.favorite_border, color: _isBookmarked ? Colors.red : Colors.white), onPressed: () { setState(() { _isBookmarked = !_isBookmarked; }); widget.onBookmarkChanged(); })
        ],
      ),
      body: SingleChildScrollView(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.all(16.0),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (widget.cafe.petStatus != PetStatus.none)
                        Container(
                          margin: const EdgeInsets.only(right: 8), padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4), 
                          decoration: BoxDecoration(color: widget.cafe.petStatus == PetStatus.friendly ? Colors.green.withValues(alpha: 0.15) : Colors.orange.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(20)),
                          child: Row(children: [Icon(Icons.pets, size: 14, color: isDark ? (widget.cafe.petStatus == PetStatus.friendly ? Colors.green.shade400 : Colors.orange.shade400) : (widget.cafe.petStatus == PetStatus.friendly ? Colors.green.shade800 : Colors.orange.shade800)), const SizedBox(width: 4), Text(widget.cafe.petStatus == PetStatus.friendly ? 'Pet Friendly' : 'Pets (Conditional)', style: TextStyle(color: isDark ? (widget.cafe.petStatus == PetStatus.friendly ? Colors.green.shade400 : Colors.orange.shade400) : (widget.cafe.petStatus == PetStatus.friendly ? Colors.green.shade800 : Colors.orange.shade800), fontWeight: FontWeight.bold, fontSize: 12))]),
                        ),
                    ],
                  ),
                  const SizedBox(height: 12),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(child: Text(widget.cafe.name, style: TextStyle(fontSize: 22, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))),
                      if (widget.cafe.rating > 0.0) Row(children: [const Icon(Icons.star, color: Colors.amber, size: 18), const SizedBox(width: 4), Text('${widget.cafe.rating} (${widget.cafe.reviews})', style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface))]),
                    ],
                  ),
                  const Divider(height: 16), 

                  Container(
                    width: double.infinity, padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isDark ? const Color(0xFF222222) : Colors.white, borderRadius: BorderRadius.circular(16), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween, crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Expanded(child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [Text(_stampLogs.isEmpty ? "Passport Unstamped" : "Passport Status", style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 15)), const SizedBox(height: 2), Text(_stampLogs.isEmpty ? "You haven't checked into this cafe yet." : "Stamped ${_stampLogs.length} time${_stampLogs.length == 1 ? '' : 's'}", style: TextStyle(fontSize: 12, color: Colors.grey.shade500))])),
                            const SizedBox(width: 12),
                            ElevatedButton.icon(style: ElevatedButton.styleFrom(backgroundColor: Colors.blueAccent, foregroundColor: Colors.white, elevation: 1, padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8), shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12))), onPressed: _addPassportStamp, icon: const Icon(Icons.stars_outlined, size: 18), label: const Text("Stamp Passport", style: TextStyle(fontWeight: FontWeight.bold)))
                          ],
                        ),
                        if (_stampLogs.isNotEmpty) ...[
                          const Padding(padding: EdgeInsets.symmetric(vertical: 10.0), child: Divider()),
                          const Text("STAMP TIMELINE HISTORY:", style: TextStyle(fontSize: 10, fontWeight: FontWeight.w900, letterSpacing: 1.0, color: Colors.grey)),
                          const SizedBox(height: 8),
                          Container(
                            constraints: const BoxConstraints(maxHeight: 120),
                            child: ListView.builder(
                              shrinkWrap: true, itemCount: _stampLogs.length,
                              itemBuilder: (context, idx) {
                                String dateIso = ""; try { dateIso = jsonDecode(_stampLogs[idx])['date'] ?? ''; } catch (_) { /* ignore */ }
                                return Padding(padding: const EdgeInsets.symmetric(vertical: 4.0), child: Row(mainAxisAlignment: MainAxisAlignment.spaceBetween, children: [Row(children: [const Icon(Icons.stars_outlined, size: 14, color: Colors.amber), const SizedBox(width: 8), Text(formatStampTimestamp(dateIso), style: const TextStyle(fontSize: 12, fontWeight: FontWeight.w600))]), GestureDetector(onTap: () => _deletePassportStamp(idx), child: Icon(Icons.remove_circle_outline, size: 16, color: Colors.red.shade300))]));
                              },
                            ),
                          )
                        ]
                      ],
                    ),
                  ),
                  const Divider(height: 24), 
                  
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.access_time, size: 18, color: iconColor), const SizedBox(width: 12),
                      Expanded(
                        child: Table(
                          columnWidths: const {0: IntrinsicColumnWidth(), 1: FixedColumnWidth(20), 2: FlexColumnWidth()},
                          children: widget.cafe.businessHours.split('\n').map((line) {
                            final isToday = line.startsWith(currentDayStr) || line.startsWith('Opens Daily');
                            final fontWeight = isToday ? FontWeight.w900 : FontWeight.w500;
                            final textColor = isToday ? theme.colorScheme.onSurface : (isDark ? Colors.white54 : Colors.black54);
                            final colonIndex = line.indexOf(':');
                            if (colonIndex != -1) {
                              return TableRow(children: [Text(line.substring(0, colonIndex).trim(), style: TextStyle(fontSize: 14, fontWeight: fontWeight, height: 1.3, color: textColor)), Text(':', textAlign: TextAlign.center, style: TextStyle(fontSize: 14, fontWeight: fontWeight, height: 1.3, color: textColor)), Text(line.substring(colonIndex + 1).trim(), style: TextStyle(fontSize: 14, fontWeight: fontWeight, height: 1.3, color: textColor))]);
                            } else {
                              return TableRow(children: [Text(line, style: TextStyle(fontSize: 14, fontWeight: fontWeight, height: 1.3, color: textColor)), const SizedBox.shrink(), const SizedBox.shrink()]);
                            }
                          }).toList(),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 12), 
                  
                  InkWell(
                    onTap: _showNavigationOptions, 
                    onLongPress: () { 
                      Clipboard.setData(ClipboardData(text: widget.cafe.address)); 
                      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('📍 Address copied!'), duration: Duration(seconds: 2), behavior: SnackBarBehavior.floating)); 
                    },
                    borderRadius: BorderRadius.circular(8),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.location_on, size: 18, color: iconColor), const SizedBox(width: 12), Expanded(child: Text(widget.cafe.address, style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: isDark ? Colors.blue.shade300 : Colors.blueAccent)))])),
                  ),
                  
                  InkWell(
                    onTap: hasPhone ? _makeCall : null, borderRadius: BorderRadius.circular(8),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(Icons.phone, size: 18, color: hasPhone ? iconColor : Colors.grey), const SizedBox(width: 12), Expanded(child: Text(hasPhone ? widget.cafe.phone : 'Phone listing unavailable', style: TextStyle(fontSize: 14, fontWeight: FontWeight.w500, color: hasPhone ? (isDark ? Colors.blue.shade300 : Colors.blueAccent) : Colors.grey)))])),
                  ),

                  InkWell(
                    onTap: _openInstagram, borderRadius: BorderRadius.circular(8),
                    child: Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [Icon(BootstrapIcons.instagram, size: 18, color: iconColor), const SizedBox(width: 12), Expanded(child: Text(getInstagramHandle(widget.cafe.instagramUrl), style: TextStyle(fontSize: 14, fontWeight: FontWeight.w700, color: isDark ? Colors.blue.shade300 : Colors.blueAccent)))])),
                  ),

                  const SizedBox(height: 20), const Divider(height: 1), const SizedBox(height: 20),
                  Text("Pin Notes", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: theme.colorScheme.onSurface)), 
                  const SizedBox(height: 12),

                  Align(
                    alignment: Alignment.centerLeft,
                    child: InkWell(
                      onTap: () => _pickDate(context), borderRadius: BorderRadius.circular(20),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6), margin: const EdgeInsets.only(bottom: 8), decoration: BoxDecoration(color: isDark ? const Color(0xFF2A2A2A) : Colors.grey.shade200, borderRadius: BorderRadius.circular(20)),
                        child: Row(mainAxisSize: MainAxisSize.min, children: [Icon(Icons.calendar_today, size: 14, color: isDark ? Colors.white70 : Colors.black87), const SizedBox(width: 6), Text(getDisplayDateForPill(_selectedNoteDate), style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600, color: isDark ? Colors.white70 : Colors.black87)), const SizedBox(width: 2), Icon(Icons.keyboard_arrow_down, size: 16, color: isDark ? Colors.white54 : Colors.black54)]),
                      ),
                    ),
                  ),

                  TextField(
                    controller: _noteController, style: TextStyle(color: theme.colorScheme.onSurface),
                    decoration: InputDecoration(
                      hintText: "E.g. The Ethiopian Pour-over was incredible...", hintStyle: TextStyle(color: Colors.grey.shade500), filled: true, fillColor: isDark ? theme.colorScheme.surface : Colors.white,
                      border: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                      enabledBorder: OutlineInputBorder(borderRadius: BorderRadius.circular(12), borderSide: BorderSide(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                      suffixIcon: IconButton(icon: const Icon(Icons.send, color: Colors.blueAccent), onPressed: _handleAddNote),
                    ),
                    textInputAction: TextInputAction.send, onSubmitted: (_) => _handleAddNote(),
                  ),
                  
                  const SizedBox(height: 16),

                  if (_notes.isEmpty)
                    Padding(padding: const EdgeInsets.symmetric(vertical: 20.0), child: Center(child: Text("No notes yet. Start writing!", style: TextStyle(color: Colors.grey.shade500, fontStyle: FontStyle.italic))))
                  else
                    ListView.builder(
                      shrinkWrap: true, physics: const NeverScrollableScrollPhysics(), itemCount: localGroupedNotes.keys.length,
                      itemBuilder: (context, index) {
                        String dateKey = localGroupedNotes.keys.elementAt(index);
                        List<Map<String, dynamic>> dayNotes = localGroupedNotes[dateKey]!;

                        return Container(
                          margin: const EdgeInsets.only(bottom: 12), padding: const EdgeInsets.all(16), decoration: BoxDecoration(color: isDark ? theme.colorScheme.surface : Colors.white, borderRadius: BorderRadius.circular(12), border: Border.all(color: isDark ? theme.dividerColor : Colors.grey.shade300)),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(children: [const Icon(Icons.calendar_today, size: 14, color: Colors.blueAccent), const SizedBox(width: 6), Text(dateKey, style: const TextStyle(fontSize: 13, fontWeight: FontWeight.bold, color: Colors.blueAccent))]),
                              const SizedBox(height: 12),
                              ...dayNotes.asMap().entries.map((entry) {
                                int localIndex = entry.key; int originalIndex = entry.value['originalIndex']; String text = entry.value['text'];
                                return Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    if (localIndex > 0) Padding(padding: const EdgeInsets.symmetric(vertical: 8.0), child: Divider(color: isDark ? theme.dividerColor : Colors.grey.shade200)),
                                    Row(
                                      crossAxisAlignment: CrossAxisAlignment.start,
                                      children: [
                                        Expanded(child: Text(text, style: TextStyle(fontSize: 14, color: theme.colorScheme.onSurface, height: 1.4))), 
                                        const SizedBox(width: 12), GestureDetector(onTap: () { setState(() { _notes.removeAt(originalIndex); }); widget.onNoteDeleted(originalIndex); }, child: Icon(Icons.delete_outline, size: 18, color: Colors.grey.shade400)),
                                      ],
                                    ),
                                  ],
                                );
                              }),
                            ],
                          ),
                        );
                      },
                    ),
                  const SizedBox(height: 32), 
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}