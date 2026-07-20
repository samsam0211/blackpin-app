import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/cafe.dart';

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
