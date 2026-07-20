import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';

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
