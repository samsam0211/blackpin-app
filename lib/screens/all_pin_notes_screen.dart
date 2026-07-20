import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cafe.dart';
import 'detail_screen.dart';

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
