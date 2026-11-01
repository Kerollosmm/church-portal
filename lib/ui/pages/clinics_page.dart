import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:material_ui/material_ui.dart';

import '../../core/l10n.dart';
import '../../core/launch.dart';
import '../../core/theme.dart';
import '../../domain/features.dart';
import '../../domain/models.dart';
import '../../domain/rules.dart';
import '../../state/providers.dart';
import '../widgets/cards.dart';
import '../widgets/common.dart';

class ClinicsPage extends ConsumerStatefulWidget {
  /// Optional initial filter from the URL (?specialty=dental).
  final String? initialSpecialty;
  const ClinicsPage({super.key, this.initialSpecialty});

  @override
  ConsumerState<ClinicsPage> createState() => _ClinicsPageState();
}

class _ClinicsPageState extends ConsumerState<ClinicsPage> {
  late String? _specialty = widget.initialSpecialty;
  bool _todayOnly = false;

  @override
  void didUpdateWidget(covariant ClinicsPage oldWidget) {
    super.didUpdateWidget(oldWidget);
    // go_router keeps this State when only ?specialty= changes.
    if (widget.initialSpecialty != oldWidget.initialSpecialty) _specialty = widget.initialSpecialty;
  }

  @override
  Widget build(BuildContext context) {
    final now = ref.watch(nowProvider).value ?? DateTime.now();
    return PageBody(
      header: PageHeader(
          title: context.tr('charityClinics'), subtitle: context.tr('clinicsIntro'), icon: Icons.local_hospital_rounded),
      children: [
        AsyncSection<List<Clinic>>(
          provider: clinicsProvider,
          retry: clinicsProvider,
          isEmpty: (d) => d.where((c) => c.active).isEmpty,
          loading: const SkeletonList(count: 6, itemHeight: 150),
          builder: (context, clinics) {
            // Clinics without a booking number fall back to the church
            // office (only while the contact details are published).
            final officePhone = ref.watch(featuresProvider).enabled(Sections.contactInfo)
                ? ref
                    .watch(settingsProvider)
                    .value
                    ?.phones
                    .where((p) => p.number.isNotEmpty)
                    .firstOrNull
                    ?.number
                : null;
            final specialties = clinicSpecialties(clinics);
            var list = filterClinics(clinics, specialty: _specialty, now: now);
            if (_todayOnly) list = list.where((c) => isClinicAvailableToday(c, now)).toList();
            return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (clinics.any((c) => c.active && c.sample)) const PendingConfirmationNote(),
              Text(context.tr('specialtyFilter'), style: const TextStyle(fontWeight: FontWeight.w700, color: AppColors.muted)),
              const SizedBox(height: 8),
              Wrap(spacing: 8, runSpacing: 8, children: [
                _chip(context.tr('allSpecialties'), _specialty == null, () => setState(() => _specialty = null)),
                for (final e in specialties.entries)
                  _chip(context.pick(e.value[0], e.value[1]), _specialty == e.key, () => setState(() => _specialty = e.key)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Switch(
                  value: _todayOnly,
                  activeThumbColor: AppColors.success,
                  onChanged: (v) => setState(() => _todayOnly = v),
                ),
                const SizedBox(width: 6),
                Text(context.tr('availableToday'), style: const TextStyle(fontWeight: FontWeight.w700)),
              ]),
              const SizedBox(height: 12),
              if (list.isEmpty)
                const EmptyState(icon: Icons.medical_services_outlined)
              else
                ResponsiveGrid(minItemWidth: 340, children: [
                  for (final c in list)
                    ClinicCard(
                      clinic: c,
                      availableToday: isClinicAvailableToday(c, now),
                      fallbackOfficePhone: officePhone,
                    ),
                ]),
              const SizedBox(height: 16),
              if (ref.watch(featuresProvider).routeEnabled('/public-services'))
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: OutlinedButton.icon(
                  onPressed: () => context.go('/public-services'),
                  icon: const Icon(Icons.volunteer_activism_rounded),
                  label: Text(context.tr('publicServices')),
                ),
              ),
            ]);
          },
        ),
      ],
    );
  }

  Widget _chip(String label, bool selected, VoidCallback onTap) => ChoiceChip(
        label: Text(label),
        selected: selected,
        showCheckmark: false,
        labelStyle: TextStyle(color: selected ? Colors.white : AppColors.burgundy, fontWeight: FontWeight.w700),
        onSelected: (_) => onTap(),
      );
}

class ClinicCard extends StatelessWidget {
  final Clinic clinic;
  final bool availableToday;

  /// Church office number shown as "Call church office" when the clinic has
  /// neither a booking phone nor a WhatsApp number (null = no fallback).
  final String? fallbackOfficePhone;
  const ClinicCard({super.key, required this.clinic, required this.availableToday, this.fallbackOfficePhone});

  /// Seeded placeholder doctor names are Arabic only ("… — يُعلن لاحقًا"):
  /// in English they are shown with the `doctorTba` string instead. The
  /// stored name is left untouched.
  static bool isPlaceholderDoctor(Clinic c) => c.sample && c.doctorName.contains('يُعلن لاحقًا');

  @override
  Widget build(BuildContext context) {
    final c = clinic;
    final doctor = !context.isAr && isPlaceholderDoctor(c)
        ? context.tr('doctorTba', {'s': c.specialtyEn.isNotEmpty ? c.specialtyEn : c.specialtyAr})
        : c.doctorName;
    final office = fallbackOfficePhone;
    final days = c.days.map((d) => weekdayLabel(context, d)).join(context.isAr ? '، ' : ', ');
    return Card(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Wrap(spacing: 8, runSpacing: 6, children: [
            Pill(context.pick(c.specialtyAr, c.specialtyEn), color: AppColors.burgundy, icon: Icons.medical_services),
            if (availableToday) Pill(context.tr('availableToday'), icon: Icons.check_circle),
          ]),
          const SizedBox(height: 10),
          Row(children: [
            Expanded(
              child: Text(doctor, style: const TextStyle(fontWeight: FontWeight.w800, fontSize: 16)),
            ),
            if (c.sample) const SampleBadge(),
          ]),
          if (context.pick(c.degreeAr, c.degreeEn).isNotEmpty)
            Text(context.pick(c.degreeAr, c.degreeEn), style: const TextStyle(color: AppColors.muted, fontSize: 13)),
          const SizedBox(height: 8),
          IconLine(Icons.calendar_today_outlined, days),
          const SizedBox(height: 2),
          TimeRangeText(c.start, c.end),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            if (c.bookingPhone.isNotEmpty)
              ActionChipButton(
                  key: const Key('bookClinic'),
                  icon: Icons.call,
                  label: '${context.tr('call')} • ${context.tr('book')}',
                  color: AppColors.burgundy,
                  onTap: () => callPhone(c.bookingPhone)),
            if (c.whatsapp.isNotEmpty)
              ActionChipButton(
                icon: Icons.chat_rounded,
                label: context.tr('whatsapp'),
                color: whatsappGreen,
                onTap: () => openWhatsApp(c.whatsapp,
                    text: context.isAr
                        ? 'أرغب في حجز موعد بعيادة ${c.specialtyAr} (${c.doctorName})'
                        : 'I would like to book an appointment at the ${c.specialtyEn} clinic ($doctor)'),
              ),
            if (c.bookingPhone.isEmpty && c.whatsapp.isEmpty && office != null)
              ActionChipButton(
                  key: const Key('callChurchOffice'),
                  icon: Icons.call,
                  label: context.tr('callChurchOffice'),
                  color: AppColors.burgundy,
                  onTap: () => callPhone(office)),
          ]),
        ]),
      ),
    );
  }
}
