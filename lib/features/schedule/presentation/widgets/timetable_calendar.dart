import 'dart:async';
import 'package:flutter/material.dart';
import 'package:trackademic/core/theme/app_colors.dart';
import 'package:trackademic/core/theme/app_dimensions.dart';

class TimetableEntry {
  final String id;
  final String courseId;
  final String courseCode;
  final String courseName;
  final String teacherName;
  final int dayIndex; // 0 = Sunday, 1 = Monday, ..., 6 = Saturday
  final String day;
  final String startTime; // e.g. "10:00"
  final String endTime; // e.g. "11:30"
  final String room;
  final String classType;
  final String status;

  const TimetableEntry({
    required this.id,
    required this.courseId,
    required this.courseCode,
    required this.courseName,
    required this.teacherName,
    required this.dayIndex,
    required this.day,
    required this.startTime,
    required this.endTime,
    required this.room,
    required this.classType,
    required this.status,
  });
}

class TimetableCalendar extends StatefulWidget {
  final List<TimetableEntry> entries;
  final bool isTeacher;
  final VoidCallback? onAddTiming;
  final void Function(TimetableEntry entry)? onEditTiming;
  final void Function(TimetableEntry entry)? onDeleteTiming;
  final VoidCallback? onRefresh;
  final String? initialCourseId;

  const TimetableCalendar({
    required this.entries,
    this.isTeacher = false,
    this.onAddTiming,
    this.onEditTiming,
    this.onDeleteTiming,
    this.onRefresh,
    this.initialCourseId,
    super.key,
  });

  @override
  State<TimetableCalendar> createState() => _TimetableCalendarState();
}

class _TimetableCalendarState extends State<TimetableCalendar> {
  bool _isWeekView = true;
  late DateTime _selectedDate;
  String? _selectedCourseFilter;
  Timer? _timeUpdateTimer;

  static const _daysOfWeek = [
    'Sunday',
    'Monday',
    'Tuesday',
    'Wednesday',
    'Thursday',
    'Friday',
    'Saturday',
  ];

  static const _months = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  // Palette of harmonious course card colors
  static const _courseColors = [
    Color(0xFF3454D1),
    Color(0xFF6D5CE7),
    Color(0xFF00B894),
    Color(0xFF0984E3),
    Color(0xFFE17055),
    Color(0xFF6C5CE7),
    Color(0xFF2D3436),
    Color(0xFF00CEC9),
  ];

  Color _getCourseColor(String courseId) {
    final hash = courseId.hashCode.abs();
    return _courseColors[hash % _courseColors.length];
  }

  @override
  void initState() {
    super.initState();
    _selectedDate = DateTime.now();
    _selectedCourseFilter = widget.initialCourseId;
    _timeUpdateTimer = Timer.periodic(const Duration(minutes: 1), (_) {
      if (mounted) {
        setState(() {});
      }
    });
  }

  @override
  void dispose() {
    _timeUpdateTimer?.cancel();
    super.dispose();
  }

  void _goToToday() {
    setState(() {
      _selectedDate = DateTime.now();
    });
  }

  void _navigatePrevious() {
    setState(() {
      if (_isWeekView) {
        _selectedDate = _selectedDate.subtract(const Duration(days: 7));
      } else {
        _selectedDate = _selectedDate.subtract(const Duration(days: 1));
      }
    });
  }

  void _navigateNext() {
    setState(() {
      if (_isWeekView) {
        _selectedDate = _selectedDate.add(const Duration(days: 7));
      } else {
        _selectedDate = _selectedDate.add(const Duration(days: 1));
      }
    });
  }

  // Get the 7 dates of the week containing _selectedDate (Sunday to Saturday)
  List<DateTime> _getWeekDates(DateTime centerDate) {
    // Dart: weekday 1 = Monday, ..., 7 = Sunday
    // dayIndex: 0 = Sunday, 1 = Monday, ..., 6 = Saturday
    final currentDayIndex = centerDate.weekday % 7;
    final sunday = centerDate.subtract(Duration(days: currentDayIndex));
    return List.generate(7, (i) => sunday.add(Duration(days: i)));
  }

  int _parseTimeToMinutes(String timeStr) {
    try {
      final parts = timeStr.trim().split(':');
      if (parts.length >= 2) {
        return int.parse(parts[0]) * 60 + int.parse(parts[1]);
      }
    } catch (_) {}
    return 480; // default 8:00 AM
  }

  void _showEntryDetail(TimetableEntry entry) {
    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        final color = _getCourseColor(entry.courseId);
        return AlertDialog(
          title: Row(
            children: [
              Container(
                width: 14,
                height: 14,
                decoration: BoxDecoration(color: color, shape: BoxShape.circle),
              ),
              const SizedBox(width: AppSpacing.small),
              Expanded(
                child: Text(
                  '${entry.courseCode} · ${entry.courseName}',
                  style: const TextStyle(
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                _buildDetailRow(Icons.calendar_today_rounded, 'Day', entry.day),
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.access_time_rounded,
                  'Time',
                  '${entry.startTime} - ${entry.endTime}',
                ),
                if (entry.room.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(Icons.room_rounded, 'Room', entry.room),
                ],
                const SizedBox(height: 8),
                _buildDetailRow(
                  Icons.category_rounded,
                  'Class Type',
                  entry.classType,
                ),
                if (entry.teacherName.isNotEmpty) ...[
                  const SizedBox(height: 8),
                  _buildDetailRow(
                    Icons.person_rounded,
                    'Teacher',
                    entry.teacherName,
                  ),
                ],
              ],
            ),
          ),
          actions: [
            if (widget.isTeacher) ...[
              if (widget.onDeleteTiming != null)
                TextButton.icon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    widget.onDeleteTiming!(entry);
                  },
                  icon: const Icon(
                    Icons.delete_outline_rounded,
                    color: AppColors.danger,
                    size: 18,
                  ),
                  label: const Text(
                    'Delete',
                    style: TextStyle(color: AppColors.danger),
                  ),
                ),
              if (widget.onEditTiming != null)
                FilledButton.tonalIcon(
                  onPressed: () {
                    Navigator.pop(dialogContext);
                    widget.onEditTiming!(entry);
                  },
                  icon: const Icon(Icons.edit_outlined, size: 18),
                  label: const Text('Edit'),
                ),
            ],
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: const Text('Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildDetailRow(IconData icon, String label, String value) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 18, color: AppColors.textTertiary),
        const SizedBox(width: AppSpacing.small),
        Text(
          '$label: ',
          style: const TextStyle(
            fontWeight: FontWeight.w600,
            fontSize: 13,
            color: AppColors.textSecondary,
          ),
        ),
        Expanded(
          child: Text(
            value,
            style: const TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 13,
              color: AppColors.textPrimary,
            ),
          ),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    var filteredEntries = widget.entries;
    if (_selectedCourseFilter != null && _selectedCourseFilter!.isNotEmpty) {
      filteredEntries = filteredEntries
          .where((e) => e.courseId == _selectedCourseFilter)
          .toList();
    }

    // Determine min and max hours for grid
    var minMinutes = 8 * 60; // 8 AM
    var maxMinutes = 18 * 60; // 6 PM
    for (final e in filteredEntries) {
      final s = _parseTimeToMinutes(e.startTime);
      final end = _parseTimeToMinutes(e.endTime);
      if (s < minMinutes) minMinutes = (s ~/ 60) * 60;
      if (end > maxMinutes) maxMinutes = ((end + 59) ~/ 60) * 60;
    }
    final startHour = minMinutes ~/ 60;
    final endHour = (maxMinutes + 59) ~/ 60;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _buildControls(),
        const SizedBox(height: AppSpacing.medium),
        _buildCourseFilterRow(),
        const SizedBox(height: AppSpacing.medium),
        Card(
          clipBehavior: Clip.antiAlias,
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.medium),
            side: const BorderSide(color: AppColors.border),
          ),
          child: _isWeekView
              ? _buildWeekView(filteredEntries, startHour, endHour)
              : _buildDayView(filteredEntries, startHour, endHour),
        ),
      ],
    );
  }

  Widget _buildControls() {
    final now = DateTime.now();
    final isCurrentDayOrWeek = _isWeekView
        ? _getWeekDates(_selectedDate).any(
            (d) =>
                d.year == now.year && d.month == now.month && d.day == now.day,
          )
        : (_selectedDate.year == now.year &&
              _selectedDate.month == now.month &&
              _selectedDate.day == now.day);

    String title;
    if (_isWeekView) {
      final week = _getWeekDates(_selectedDate);
      final first = week.first;
      final last = week.last;
      title =
          '${_months[first.month - 1]} ${first.day} – ${_months[last.month - 1]} ${last.day}, ${last.year}';
    } else {
      title =
          '${_daysOfWeek[_selectedDate.weekday % 7]}, ${_months[_selectedDate.month - 1]} ${_selectedDate.day}, ${_selectedDate.year}';
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final isNarrow = constraints.maxWidth < 650;

        final navSection = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                backgroundColor: isCurrentDayOrWeek
                    ? AppColors.primary.withValues(alpha: 0.1)
                    : null,
              ),
              onPressed: _goToToday,
              child: const Text(
                'Today',
                style: TextStyle(fontWeight: FontWeight.bold),
              ),
            ),
            const SizedBox(width: AppSpacing.small),
            IconButton(
              iconSize: 20,
              tooltip: 'Previous',
              onPressed: _navigatePrevious,
              icon: const Icon(Icons.chevron_left_rounded),
            ),
            IconButton(
              iconSize: 20,
              tooltip: 'Next',
              onPressed: _navigateNext,
              icon: const Icon(Icons.chevron_right_rounded),
            ),
            const SizedBox(width: AppSpacing.small),
            Text(
              title,
              style: const TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w800,
                color: AppColors.textPrimary,
              ),
            ),
          ],
        );

        final toggleAndActions = Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            SegmentedButton<bool>(
              segments: const [
                ButtonSegment<bool>(value: false, label: Text('Day')),
                ButtonSegment<bool>(value: true, label: Text('Week')),
              ],
              selected: {_isWeekView},
              onSelectionChanged: (set) {
                setState(() {
                  _isWeekView = set.first;
                });
              },
            ),
            if (widget.onRefresh != null) ...[
              const SizedBox(width: AppSpacing.small),
              IconButton(
                tooltip: 'Refresh',
                onPressed: widget.onRefresh,
                icon: const Icon(Icons.refresh_rounded),
              ),
            ],
            if (widget.isTeacher && widget.onAddTiming != null) ...[
              const SizedBox(width: AppSpacing.small),
              FilledButton.icon(
                onPressed: widget.onAddTiming,
                icon: const Icon(Icons.add_rounded, size: 18),
                label: const Text('Add class'),
              ),
            ],
          ],
        );

        if (isNarrow) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: navSection,
              ),
              const SizedBox(height: AppSpacing.small),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: toggleAndActions,
              ),
            ],
          );
        }

        return Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [navSection, toggleAndActions],
        );
      },
    );
  }

  Widget _buildCourseFilterRow() {
    final coursesMap = <String, String>{};
    for (final e in widget.entries) {
      coursesMap[e.courseId] = '${e.courseCode} · ${e.courseName}';
    }

    if (coursesMap.length <= 1) return const SizedBox.shrink();

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          const Text(
            'Filter by course: ',
            style: TextStyle(
              fontSize: 12,
              fontWeight: FontWeight.w600,
              color: AppColors.textSecondary,
            ),
          ),
          const SizedBox(width: 8),
          FilterChip(
            selected: _selectedCourseFilter == null,
            label: const Text('All Courses'),
            onSelected: (_) {
              setState(() {
                _selectedCourseFilter = null;
              });
            },
          ),
          for (final entry in coursesMap.entries) ...[
            const SizedBox(width: 6),
            FilterChip(
              selected: _selectedCourseFilter == entry.key,
              label: Text(entry.value),
              onSelected: (selected) {
                setState(() {
                  _selectedCourseFilter = selected ? entry.key : null;
                });
              },
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildCurrentTimeIndicator(
    double top, {
    double left = 0,
    double right = 0,
  }) {
    const dotSize = 8.0;
    const lineHeight = 2.0;
    const indicatorColor = Color(0xFFEA4335);

    return Positioned(
      key: const ValueKey('current_time_indicator'),
      top: top - (dotSize / 2),
      left: left,
      right: right,
      child: IgnorePointer(
        child: Row(
          children: [
            Container(
              width: dotSize,
              height: dotSize,
              decoration: const BoxDecoration(
                color: indicatorColor,
                shape: BoxShape.circle,
              ),
            ),
            Expanded(
              child: Container(height: lineHeight, color: indicatorColor),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayView(
    List<TimetableEntry> entries,
    int startHour,
    int endHour,
  ) {
    final selectedDayIndex = _selectedDate.weekday % 7;
    final dayEntries = entries
        .where((e) => e.dayIndex == selectedDayIndex)
        .toList();

    const hourHeight = 64.0;
    final totalHours = endHour - startHour;
    final gridHeight = totalHours * hourHeight;

    final now = DateTime.now();
    final isSelectedDayToday =
        _selectedDate.year == now.year &&
        _selectedDate.month == now.month &&
        _selectedDate.day == now.day;
    final currentMinutes = now.hour * 60 + now.minute;
    final currentTimeTop =
        (currentMinutes - (startHour * 60)) * (hourHeight / 60.0);
    final showCurrentTime =
        isSelectedDayToday &&
        currentTimeTop >= 0 &&
        currentTimeTop <= gridHeight;

    return SingleChildScrollView(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Time labels
          SizedBox(
            width: 60,
            child: Column(
              children: List.generate(totalHours + 1, (i) {
                final hour = startHour + i;
                final label = hour == 0
                    ? '12 AM'
                    : hour < 12
                    ? '$hour AM'
                    : hour == 12
                    ? '12 PM'
                    : '${hour - 12} PM';
                return SizedBox(
                  height: i == totalHours ? 20 : hourHeight,
                  child: Align(
                    alignment: Alignment.topCenter,
                    child: Text(
                      label,
                      style: const TextStyle(
                        fontSize: 11,
                        color: AppColors.textTertiary,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                  ),
                );
              }),
            ),
          ),

          // Day Canvas
          Expanded(
            child: Container(
              height: gridHeight,
              decoration: const BoxDecoration(
                border: Border(left: BorderSide(color: AppColors.border)),
              ),
              child: Stack(
                children: [
                  // Horizontal hour divider lines
                  for (var i = 0; i <= totalHours; i++)
                    Positioned(
                      top: i * hourHeight,
                      left: 0,
                      right: 0,
                      child: const Divider(height: 1, color: AppColors.border),
                    ),

                  // Scheduled events
                  if (dayEntries.isEmpty)
                    const Center(
                      child: Text(
                        'No classes scheduled for this day.',
                        style: TextStyle(color: AppColors.textSecondary),
                      ),
                    )
                  else
                    for (final entry in dayEntries)
                      _buildPositionedBlock(entry, startHour, hourHeight, 0, 1),

                  // Current time line indicator (today only)
                  if (showCurrentTime)
                    _buildCurrentTimeIndicator(currentTimeTop),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildWeekView(
    List<TimetableEntry> entries,
    int startHour,
    int endHour,
  ) {
    final weekDates = _getWeekDates(_selectedDate);
    final now = DateTime.now();

    const hourHeight = 64.0;
    final totalHours = endHour - startHour;
    final gridHeight = totalHours * hourHeight;
    const colWidth = 120.0;

    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: SizedBox(
        width: 60 + (colWidth * 7),
        child: Column(
          children: [
            // Week headers
            Container(
              decoration: BoxDecoration(
                color: AppColors.surface,
                border: const Border(
                  bottom: BorderSide(color: AppColors.border),
                ),
              ),
              child: Row(
                children: [
                  const SizedBox(width: 60), // Space above time labels
                  for (var i = 0; i < 7; i++) ...[
                    _buildDayHeader(weekDates[i], i, colWidth, now),
                  ],
                ],
              ),
            ),

            // Time grid with columns
            SingleChildScrollView(
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  // Left hour labels
                  SizedBox(
                    width: 60,
                    child: Column(
                      children: List.generate(totalHours + 1, (i) {
                        final hour = startHour + i;
                        final label = hour == 0
                            ? '12 AM'
                            : hour < 12
                            ? '$hour AM'
                            : hour == 12
                            ? '12 PM'
                            : '${hour - 12} PM';
                        return SizedBox(
                          height: i == totalHours ? 20 : hourHeight,
                          child: Align(
                            alignment: Alignment.topCenter,
                            child: Text(
                              label,
                              style: const TextStyle(
                                fontSize: 11,
                                color: AppColors.textTertiary,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ),
                        );
                      }),
                    ),
                  ),

                  // 7 Day columns
                  for (var dayIdx = 0; dayIdx < 7; dayIdx++) ...[
                    Builder(
                      builder: (context) {
                        final isColumnToday =
                            weekDates[dayIdx].year == now.year &&
                            weekDates[dayIdx].month == now.month &&
                            weekDates[dayIdx].day == now.day;
                        final currentMinutes = now.hour * 60 + now.minute;
                        final currentTimeTop =
                            (currentMinutes - (startHour * 60)) *
                            (hourHeight / 60.0);
                        final showCurrentTime =
                            isColumnToday &&
                            currentTimeTop >= 0 &&
                            currentTimeTop <= gridHeight;

                        return Container(
                          width: colWidth,
                          height: gridHeight,
                          decoration: BoxDecoration(
                            border: const Border(
                              left: BorderSide(color: AppColors.border),
                            ),
                            color: isColumnToday
                                ? AppColors.primary.withValues(alpha: 0.03)
                                : null,
                          ),
                          child: Stack(
                            children: [
                              // Horizontal hour dividers
                              for (var i = 0; i <= totalHours; i++)
                                Positioned(
                                  top: i * hourHeight,
                                  left: 0,
                                  right: 0,
                                  child: const Divider(
                                    height: 1,
                                    color: AppColors.border,
                                  ),
                                ),

                              // Positioned event cards for this day
                              ..._buildDayColumnBlocks(
                                entries
                                    .where((e) => e.dayIndex == dayIdx)
                                    .toList(),
                                startHour,
                                hourHeight,
                              ),

                              // Current-time line indicator (today column only)
                              if (showCurrentTime)
                                _buildCurrentTimeIndicator(currentTimeTop),
                            ],
                          ),
                        );
                      },
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildDayHeader(
    DateTime date,
    int dayIndex,
    double width,
    DateTime now,
  ) {
    final isToday =
        date.year == now.year && date.month == now.month && date.day == now.day;
    return Container(
      width: width,
      padding: const EdgeInsets.symmetric(vertical: 10),
      decoration: BoxDecoration(
        color: isToday ? AppColors.primary.withValues(alpha: 0.08) : null,
        border: const Border(left: BorderSide(color: AppColors.border)),
      ),
      child: Column(
        children: [
          Text(
            _daysOfWeek[dayIndex].substring(0, 3).toUpperCase(),
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.w700,
              color: isToday ? AppColors.primary : AppColors.textSecondary,
            ),
          ),
          const SizedBox(height: 2),
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: isToday ? AppColors.primary : Colors.transparent,
              shape: BoxShape.circle,
            ),
            child: Text(
              '${date.day}',
              style: TextStyle(
                fontSize: 14,
                fontWeight: FontWeight.w900,
                color: isToday ? Colors.white : AppColors.textPrimary,
              ),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _buildDayColumnBlocks(
    List<TimetableEntry> dayEntries,
    int startHour,
    double hourHeight,
  ) {
    if (dayEntries.isEmpty) return const [];

    dayEntries.sort(
      (a, b) => _parseTimeToMinutes(
        a.startTime,
      ).compareTo(_parseTimeToMinutes(b.startTime)),
    );

    final widgets = <Widget>[];
    for (var i = 0; i < dayEntries.length; i++) {
      widgets.add(
        _buildPositionedBlock(dayEntries[i], startHour, hourHeight, 0, 1),
      );
    }
    return widgets;
  }

  Widget _buildPositionedBlock(
    TimetableEntry entry,
    int startHour,
    double hourHeight,
    int colIndex,
    int colCount,
  ) {
    final startMin = _parseTimeToMinutes(entry.startTime);
    final endMin = _parseTimeToMinutes(entry.endTime);
    final top = (startMin - (startHour * 60)) * (hourHeight / 60.0);
    final height = ((endMin - startMin) * (hourHeight / 60.0)).clamp(
      36.0,
      300.0,
    );
    final color = _getCourseColor(entry.courseId);

    return Positioned(
      top: top + 1,
      left: 2,
      right: 2,
      height: height - 2,
      child: InkWell(
        onTap: () => _showEntryDetail(entry),
        borderRadius: BorderRadius.circular(6),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
          decoration: BoxDecoration(
            color: color.withValues(alpha: 0.12),
            borderRadius: BorderRadius.circular(6),
            border: Border.all(color: color.withValues(alpha: 0.6), width: 1.2),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                entry.courseCode,
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.w900,
                  color: color,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              Text(
                '${entry.startTime} - ${entry.endTime}',
                style: const TextStyle(
                  fontSize: 10,
                  fontWeight: FontWeight.w600,
                  color: AppColors.textSecondary,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (entry.room.isNotEmpty)
                Text(
                  entry.room,
                  style: const TextStyle(
                    fontSize: 9,
                    color: AppColors.textTertiary,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ),
      ),
    );
  }
}
