import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import '../models/cafe.dart';
import 'detail_screen.dart';

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
