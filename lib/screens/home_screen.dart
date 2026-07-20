import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:http/http.dart' as http;
import 'package:csv/csv.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import '../models/cafe.dart';
import 'filtered_cafe_list_screen.dart';
import 'passport_stamps_screen.dart';
import 'all_pin_notes_screen.dart';
import 'detail_screen.dart';
import '../main.dart';

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
