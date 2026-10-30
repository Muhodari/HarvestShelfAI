/// Time formats used across the app (24-hour, no locale data needed offline).
library;

String _two(int v) => v.toString().padLeft(2, '0');

String formatClock(DateTime t) => '${_two(t.hour)}:${_two(t.minute)}';

String formatTime(DateTime t) =>
    '${t.year}-${_two(t.month)}-${_two(t.day)} ${formatClock(t)}';
