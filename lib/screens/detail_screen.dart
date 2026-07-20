import 'dart:io';
import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:bootstrap_icons/bootstrap_icons.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:geolocator/geolocator.dart';
import 'package:share_plus/share_plus.dart';
import 'package:map_launcher/map_launcher.dart' hide MapType;
import 'package:flutter_svg/flutter_svg.dart';
import '../models/cafe.dart';

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