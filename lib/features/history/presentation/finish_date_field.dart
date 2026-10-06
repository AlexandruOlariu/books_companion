import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../../library/domain/models.dart';

class FinishDateField extends StatefulWidget {
  final ValueChanged<PartialDate?> onChanged;
  const FinishDateField({super.key, required this.onChanged});
  @override
  State<FinishDateField> createState() => _FinishDateFieldState();
}

class _FinishDateFieldState extends State<FinishDateField> {
  DatePrecision? precision;
  int? year, month;
  PartialDate? chosen;
  void publish() {
    chosen = switch (precision) {
      DatePrecision.unknown => const PartialDate.unknown(),
      DatePrecision.year when year != null => PartialDate(
        DatePrecision.year,
        year.toString().padLeft(4, '0'),
      ),
      DatePrecision.month when year != null && month != null => PartialDate(
        DatePrecision.month,
        '${year.toString().padLeft(4, '0')}-${month.toString().padLeft(2, '0')}',
      ),
      DatePrecision.day => chosen,
      _ => null,
    };
    widget.onChanged(chosen);
  }

  @override
  Widget build(BuildContext context) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Text(
        'When did you finish it?',
        style: Theme.of(context).textTheme.titleMedium,
      ),
      const SizedBox(height: 8),
      DropdownButtonFormField<DatePrecision>(
        initialValue: precision,
        decoration: const InputDecoration(labelText: 'Date precision'),
        items: const [
          DropdownMenuItem(value: DatePrecision.day, child: Text('Exact date')),
          DropdownMenuItem(
            value: DatePrecision.month,
            child: Text('Month and year'),
          ),
          DropdownMenuItem(value: DatePrecision.year, child: Text('Year only')),
          DropdownMenuItem(
            value: DatePrecision.unknown,
            child: Text("I don’t remember"),
          ),
        ],
        onChanged: (v) {
          setState(() {
            precision = v;
            chosen = null;
            year = null;
            month = null;
          });
          publish();
        },
      ),
      if (precision == DatePrecision.day)
        Padding(
          padding: const EdgeInsets.only(top: 12),
          child: OutlinedButton.icon(
            icon: const Icon(Icons.calendar_today_outlined),
            label: Text(chosen?.label ?? 'Choose and confirm date'),
            onPressed: () async {
              final now = DateTime.now();
              final date = await showDatePicker(
                context: context,
                initialDate: now,
                firstDate: DateTime(1),
                lastDate: now,
              );
              if (date != null && mounted) {
                setState(
                  () => chosen = PartialDate(
                    DatePrecision.day,
                    DateFormat('yyyy-MM-dd').format(date),
                  ),
                );
                publish();
              }
            },
          ),
        ),
      if (precision == DatePrecision.year ||
          precision == DatePrecision.month) ...[
        const SizedBox(height: 12),
        TextFormField(
          key: ValueKey(precision),
          decoration: const InputDecoration(
            labelText: 'Year',
            hintText: 'e.g. 2019',
          ),
          keyboardType: TextInputType.number,
          onChanged: (v) {
            final parsed = int.tryParse(v);
            year = parsed != null && parsed > 0 && parsed <= DateTime.now().year
                ? parsed
                : null;
            publish();
          },
        ),
      ],
      if (precision == DatePrecision.month) ...[
        const SizedBox(height: 12),
        DropdownButtonFormField<int>(
          decoration: const InputDecoration(labelText: 'Month'),
          items: List.generate(
            12,
            (i) => DropdownMenuItem(
              value: i + 1,
              child: Text(DateFormat.MMMM().format(DateTime(2000, i + 1))),
            ),
          ),
          onChanged: (v) {
            month = v;
            publish();
          },
        ),
      ],
      if (precision == DatePrecision.unknown)
        const Padding(
          padding: EdgeInsets.only(top: 12),
          child: Text('Saved in All time, without an invented date.'),
        ),
    ],
  );
}
