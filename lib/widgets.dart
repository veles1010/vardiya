import 'package:flutter/material.dart';

import 'domain.dart';

const monthNames = [
  'Ocak',
  'Şubat',
  'Mart',
  'Nisan',
  'Mayıs',
  'Haziran',
  'Temmuz',
  'Ağustos',
  'Eylül',
  'Ekim',
  'Kasım',
  'Aralık',
];
const weekNames = ['Pzt', 'Sal', 'Çar', 'Per', 'Cum', 'Cmt', 'Paz'];
String two(int n) => n.toString().padLeft(2, '0');
String clockText(DateTime d) => '${two(d.hour)}:${two(d.minute)}';
String minuteText(int m) => '${two(m ~/ 60)}:${two(m % 60)}';
String dateText(DateTime d) => '${d.day} ${monthNames[d.month - 1]} ${d.year}';
String monthText(DateTime d) => '${monthNames[d.month - 1]} ${d.year}';
String durationText(double minutes) {
  final n = minutes.round();
  return '${n ~/ 60} sa ${two(n % 60)} dk';
}

String kindText(EntryKind kind) => switch (kind) {
  EntryKind.work => 'Vardiya',
  EntryKind.leave => 'İzin',
  EntryKind.rest => 'Dinlenme',
};
IconData shiftIcon(Shift s) => switch (s.kind) {
  EntryKind.leave => Icons.beach_access_outlined,
  EntryKind.rest => Icons.weekend_outlined,
  EntryKind.work =>
    s.start.hour >= 20 || s.start.hour < 6
        ? Icons.nightlight_outlined
        : Icons.wb_sunny_outlined,
};
Color shiftColor(Shift s) => switch (s.kind) {
  EntryKind.leave => const Color(0xff197b62),
  EntryKind.rest => const Color(0xff687589),
  EntryKind.work =>
    s.start.hour >= 20 || s.start.hour < 6
        ? const Color(0xff6c55a3)
        : s.start.hour >= 12
        ? const Color(0xffa15e20)
        : const Color(0xff247e93),
};
String shiftTime(Shift s) => s.kind != EntryKind.work
    ? 'Tüm gün'
    : '${clockText(s.start)} – ${clockText(s.end)}${dayOf(s.end) != dayOf(s.start) ? ' (+1 gün)' : ''}';
String errorText(Object error) => error is RuleViolation
    ? error.message
    : 'Kayıt cihazda saklanamadı. Lütfen tekrar deneyin. Mevcut veriler korunuyor.';

class Surface extends StatelessWidget {
  const Surface({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(20),
  });
  final Widget child;
  final EdgeInsets padding;
  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    decoration: BoxDecoration(
      color: Colors.white,
      borderRadius: BorderRadius.circular(20),
      border: Border.all(color: const Color(0xffccd7da)),
    ),
    child: Material(type: MaterialType.transparency, child: child),
  );
}

class EmptyState extends StatelessWidget {
  const EmptyState(
    this.text, {
    super.key,
    this.icon = Icons.event_available_outlined,
  });
  final String text;
  final IconData icon;
  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.symmetric(vertical: 28, horizontal: 16),
    child: Column(
      children: [
        Icon(icon, size: 32, color: Theme.of(context).colorScheme.primary),
        const SizedBox(height: 12),
        Text(
          text,
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.bodyMedium,
        ),
      ],
    ),
  );
}

class ShiftTile extends StatelessWidget {
  const ShiftTile({
    super.key,
    required this.shift,
    this.onEdit,
    this.onDelete,
    this.employeeName,
    this.day,
  });
  final Shift shift;
  final VoidCallback? onEdit;
  final VoidCallback? onDelete;
  final String? employeeName;
  final DateTime? day;
  @override
  Widget build(BuildContext context) {
    final color = shiftColor(shift);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Container(
        decoration: BoxDecoration(
          color: color.withValues(alpha: .06),
          borderRadius: BorderRadius.circular(14),
          border: Border(left: BorderSide(color: color, width: 4)),
        ),
        padding: const EdgeInsets.all(14),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(shiftIcon(shift), color: color, size: 22),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (employeeName != null)
                    Text(
                      employeeName!,
                      style: const TextStyle(fontWeight: FontWeight.w700),
                    ),
                  Text(
                    shift.label,
                    style: TextStyle(color: color, fontWeight: FontWeight.w700),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    shiftTime(shift),
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  if (day != null && dayOf(shift.start).isBefore(dayOf(day!)))
                    Text(
                      '${dateText(shift.start)} gününden devam ediyor',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (shift.kind == EntryKind.work)
                    Text(
                      'Mola ${shift.breakMinutes} dk · Net ${durationText(shift.netMinutes)}',
                      style: Theme.of(context).textTheme.bodySmall,
                    ),
                  if (shift.note.isNotEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Text(shift.note),
                    ),
                ],
              ),
            ),
            if (onEdit != null)
              PopupMenuButton<String>(
                tooltip: 'Kayıt işlemleri',
                onSelected: (v) => v == 'edit' ? onEdit!() : onDelete!(),
                itemBuilder: (_) => const [
                  PopupMenuItem(value: 'edit', child: Text('Düzenle')),
                  PopupMenuItem(value: 'delete', child: Text('Sil')),
                ],
              ),
          ],
        ),
      ),
    );
  }
}

class PeriodNav extends StatelessWidget {
  const PeriodNav({
    super.key,
    required this.label,
    required this.previous,
    required this.next,
    required this.today,
  });
  final String label;
  final VoidCallback previous, next, today;
  @override
  Widget build(BuildContext context) => Wrap(
    crossAxisAlignment: WrapCrossAlignment.center,
    spacing: 4,
    children: [
      IconButton(
        tooltip: 'Önceki dönem',
        onPressed: previous,
        icon: const Icon(Icons.chevron_left),
      ),
      Text(label, style: Theme.of(context).textTheme.titleMedium),
      IconButton(
        tooltip: 'Sonraki dönem',
        onPressed: next,
        icon: const Icon(Icons.chevron_right),
      ),
      TextButton(onPressed: today, child: const Text('Bugün')),
    ],
  );
}

class MonthCalendar extends StatelessWidget {
  const MonthCalendar({
    super.key,
    required this.month,
    required this.selected,
    required this.shifts,
    required this.onSelect,
    required this.onMonth,
  });
  final DateTime month, selected;
  final List<Shift> shifts;
  final ValueChanged<DateTime> onSelect, onMonth;
  @override
  Widget build(BuildContext context) {
    final first = monthOf(month);
    final gridStart = weekOf(first);
    final last = DateTime.utc(first.year, first.month + 1, 0);
    final count = ((first.weekday - 1 + last.day) / 7).ceil() * 7;
    return Surface(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          PeriodNav(
            label: monthText(month),
            previous: () => onMonth(DateTime.utc(month.year, month.month - 1)),
            next: () => onMonth(DateTime.utc(month.year, month.month + 1)),
            today: () {
              onMonth(monthOf(DateTime.now()));
              onSelect(dayOf(DateTime.now()));
            },
          ),
          const SizedBox(height: 12),
          Row(
            children: weekNames
                .map(
                  (d) => Expanded(
                    child: Center(
                      child: Text(
                        d,
                        style: const TextStyle(
                          color: Color(0xff52616f),
                          fontSize: 12,
                        ),
                      ),
                    ),
                  ),
                )
                .toList(),
          ),
          const SizedBox(height: 8),
          LayoutBuilder(
            builder: (context, constraints) => GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              itemCount: count,
              gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 7,
                mainAxisExtent: constraints.maxWidth < 420 ? 52 : 76,
                crossAxisSpacing: 3,
                mainAxisSpacing: 3,
              ),
              itemBuilder: (context, i) {
                final day = gridStart.add(Duration(days: i));
                final entries = shifts
                    .where(
                      (s) =>
                          s.intersects(day, day.add(const Duration(days: 1))),
                    )
                    .toList();
                final active = day == dayOf(selected);
                final isToday = day == dayOf(DateTime.now());
                return Semantics(
                  label: '${dateText(day)}, ${entries.length} kayıt',
                  selected: active,
                  child: Material(
                    color: active
                        ? const Color(0xff176b5d)
                        : day.month == month.month
                        ? const Color(0xfff6f8f8)
                        : Colors.white,
                    borderRadius: BorderRadius.circular(10),
                    child: InkWell(
                      borderRadius: BorderRadius.circular(10),
                      onTap: () => onSelect(day),
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Text(
                            '${day.day}',
                            style: TextStyle(
                              fontSize: 14,
                              fontWeight: active || isToday
                                  ? FontWeight.w800
                                  : FontWeight.w500,
                              color: active
                                  ? Colors.white
                                  : day.month == month.month
                                  ? const Color(0xff263746)
                                  : const Color(0xffaab2b9),
                            ),
                          ),
                          const SizedBox(height: 3),
                          if (entries.isNotEmpty)
                            Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: entries
                                  .take(3)
                                  .map(
                                    (s) => Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 1,
                                      ),
                                      child: Icon(
                                        shiftIcon(s),
                                        size: 10,
                                        color: active
                                            ? Colors.white
                                            : shiftColor(s),
                                      ),
                                    ),
                                  )
                                  .toList(),
                            )
                          else
                            const SizedBox(height: 10),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 12),
          const Wrap(
            spacing: 14,
            runSpacing: 6,
            children: [
              Text('☀ Vardiya', style: TextStyle(fontSize: 12)),
              Text('☾ Gece', style: TextStyle(fontSize: 12)),
              Text('İzin / Dinlenme', style: TextStyle(fontSize: 12)),
            ],
          ),
        ],
      ),
    );
  }
}
