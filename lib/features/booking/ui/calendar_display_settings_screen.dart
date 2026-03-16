// lib/features/booking/ui/calendar_display_settings_screen.dart
//
// Full-screen calendar display settings. Four section cards, compact numeric
// inputs with units, Form validation, sticky Save bar, Reset to defaults.
// UI-only; no schema or backend changes.

import 'package:cloud_functions/cloud_functions.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';

import '../../../data/repositories/calendar_display_settings_repository.dart';
import '../../../models/calendar_display_settings.dart';
import '../../../ui/design_tokens.dart';
import 'calendar_display_settings_validation.dart';

const String _introText =
    'Control how the booking calendar looks and behaves for everyone in this clinic. '
    'These settings only affect the display—they do not change when you can book or your availability.';

/// Reusable card for a settings section (title, optional subtitle, children).
/// White surface, subtle border; optional hover lift on desktop.
class SettingsSectionCard extends StatefulWidget {
  const SettingsSectionCard({
    super.key,
    required this.title,
    this.subtitle,
    required this.children,
  });

  final String title;
  final String? subtitle;
  final List<Widget> children;

  @override
  State<SettingsSectionCard> createState() => _SettingsSectionCardState();
}

class _SettingsSectionCardState extends State<SettingsSectionCard> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isDesktop = MediaQuery.sizeOf(context).width >= 1100;
    return MouseRegion(
      onEnter: isDesktop ? (_) => setState(() => _hovered = true) : null,
      onExit: isDesktop ? (_) => setState(() => _hovered = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 150),
        child: Card(
          elevation: _hovered ? 1 : 0,
          color: Colors.white,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(AppRadius.card),
            side: BorderSide(
              color: AppColors.settingsCardBorder,
              width: 1,
            ),
          ),
          child: Padding(
            padding: const EdgeInsets.all(20),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(
                  widget.title,
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.w600,
                    color: theme.colorScheme.onSurface,
                    letterSpacing: -0.2,
                  ),
                ),
                if (widget.subtitle != null) ...[
                  const SizedBox(height: 4),
                  Text(
                    widget.subtitle!,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.65),
                      fontSize: 12,
                    ),
                  ),
                ],
                const SizedBox(height: 16),
                ...widget.children,
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Compact row: label (and optional helper) on the left, fixed-width numeric field + unit on the right.
class NumberSettingRow extends StatelessWidget {
  const NumberSettingRow({
    super.key,
    required this.label,
    this.helperText,
    required this.controller,
    required this.unit,
    required this.validator,
    this.keyboardType = TextInputType.number,
    this.inputFormatters,
    this.onChanged,
  });

  final String label;
  final String? helperText;
  final TextEditingController controller;
  final String unit;
  final String? Function(String?) validator;
  final TextInputType keyboardType;
  final List<TextInputFormatter>? inputFormatters;
  final ValueChanged<String>? onChanged;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                label,
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: theme.colorScheme.onSurface,
                ),
              ),
              if (helperText != null) ...[
                const SizedBox(height: 2),
                Text(
                  helperText!,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    fontSize: 11,
                  ),
                ),
              ],
            ],
          ),
        ),
        const SizedBox(width: 16),
        SizedBox(
          width: 104,
          child: TextFormField(
            controller: controller,
            keyboardType: keyboardType,
            inputFormatters: inputFormatters,
            decoration: InputDecoration(
              suffixText: unit,
              suffixStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
              ),
              filled: true,
              fillColor: AppColors.inputFill,
              contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              errorStyle: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.error,
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: const BorderSide(
                  color: AppColors.settingsCardBorder,
                  width: 1,
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(
                  color: theme.colorScheme.primary,
                  width: 1.5,
                ),
              ),
              errorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.colorScheme.error, width: 1),
              ),
              focusedErrorBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(10),
                borderSide: BorderSide(color: theme.colorScheme.error, width: 1.5),
              ),
            ),
            validator: validator,
            onChanged: (v) {
              onChanged?.call(v);
              if (context.mounted) {
                Form.maybeOf(context)?.validate();
              }
            },
          ),
        ),
      ],
    );
  }
}

class CalendarDisplaySettingsScreen extends StatefulWidget {
  const CalendarDisplaySettingsScreen({
    super.key,
    required this.clinicId,
    this.initial,
    this.repo,
    this.onSaved,
  });

  final String clinicId;
  final CalendarDisplaySettings? initial;
  final CalendarDisplaySettingsRepository? repo;
  /// When set (e.g. embedded in Settings), called after save instead of popping.
  final void Function(CalendarDisplaySettings)? onSaved;

  @override
  State<CalendarDisplaySettingsScreen> createState() =>
      _CalendarDisplaySettingsScreenState();
}

class _CalendarDisplaySettingsScreenState
    extends State<CalendarDisplaySettingsScreen> {
  /// Staged edits; only persisted when user taps Save.
  late CalendarDisplaySettings _draft;

  late final TextEditingController _startHourController;
  late final TextEditingController _endHourController;
  late final TextEditingController _minutesPerBlockController;
  late final TextEditingController _slotHeightController;
  late final TextEditingController _timePickerIncrementController;

  final GlobalKey<FormState> _formKey = GlobalKey<FormState>();
  bool _saving = false;

  @override
  void initState() {
    super.initState();
    _draft = widget.initial ?? CalendarDisplaySettings.defaults;
    _startHourController = TextEditingController(text: _draft.displayStartHour.toString());
    _endHourController = TextEditingController(text: _draft.displayEndHour.toString());
    _minutesPerBlockController = TextEditingController(text: _draft.minutesPerBlock.toString());
    _slotHeightController = TextEditingController(text: _draft.slotHeightPx.toString());
    _timePickerIncrementController = TextEditingController(text: _draft.timePickerIncrementMinutes.toString());
    // When embedded in Settings (no initial), load saved settings so returning to the tab shows them.
    if (widget.initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _loadSavedSettings());
    }
  }

  Future<void> _loadSavedSettings() async {
    if (!mounted) return;
    final repo = widget.repo ?? context.read<CalendarDisplaySettingsRepository>();
    try {
      final saved = await repo.getSettings(widget.clinicId);
      if (!mounted) return;
      setState(() => _draft = saved);
      _syncControllersFromDraft();
    } catch (_) {
      // Keep defaults on error
    }
  }

  @override
  void dispose() {
    _startHourController.dispose();
    _endHourController.dispose();
    _minutesPerBlockController.dispose();
    _slotHeightController.dispose();
    _timePickerIncrementController.dispose();
    super.dispose();
  }

  void _syncControllersFromDraft() {
    _startHourController.text = _draft.displayStartHour.toString();
    _endHourController.text = _draft.displayEndHour.toString();
    _minutesPerBlockController.text = _draft.minutesPerBlock.toString();
    _slotHeightController.text = _draft.slotHeightPx.toString();
    _timePickerIncrementController.text = _draft.timePickerIncrementMinutes.toString();
  }

  bool _draftEqualsInitial() {
    final a = _draft;
    final b = widget.initial ?? CalendarDisplaySettings.defaults;
    return a.displayStartHour == b.displayStartHour &&
        a.displayEndHour == b.displayEndHour &&
        a.slotMinutes == b.slotMinutes &&
        a.slotHeightPx == b.slotHeightPx &&
        a.timePickerIncrement == b.timePickerIncrement &&
        a.showCurrentTimeIndicator == b.showCurrentTimeIndicator &&
        a.hidePatientNames == b.hidePatientNames &&
        a.confirmMove == b.confirmMove &&
        a.showFinancialIndicators == b.showFinancialIndicators &&
        a.showWaitlistMatches == b.showWaitlistMatches &&
        a.smartOneDayView == b.smartOneDayView &&
        a.defaultView == b.defaultView &&
        a.weekStartsOn == b.weekStartsOn &&
        a.showWeekends == b.showWeekends &&
        a.showClosedDayLabel == b.showClosedDayLabel &&
        a.condensedHeader == b.condensedHeader;
  }

  Future<void> _save() async {
    if (!_formKey.currentState!.validate()) return;
    final start = int.tryParse(_startHourController.text) ?? _draft.displayStartHour;
    final end = int.tryParse(_endHourController.text) ?? _draft.displayEndHour;
    final block = int.tryParse(_minutesPerBlockController.text) ?? _draft.minutesPerBlock;
    final height = double.tryParse(_slotHeightController.text) ?? _draft.slotHeightPx;
    final increment = int.tryParse(_timePickerIncrementController.text) ?? _draft.timePickerIncrementMinutes;
    final updated = CalendarDisplaySettings(
      displayStartHour: start.clamp(0, 23),
      displayEndHour: end.clamp(1, 24),
      slotMinutes: block.clamp(5, 60),
      slotHeightPx: height.clamp(16.0, 96.0),
      timePickerIncrement: increment.clamp(1, 60),
      confirmMove: _draft.confirmMove,
      showFinancialIndicators: _draft.showFinancialIndicators,
      showWaitlistMatches: _draft.showWaitlistMatches,
      clientNameSeparateLine: _draft.clientNameSeparateLine,
      showCurrentTimeIndicator: _draft.showCurrentTimeIndicator,
      hidePatientNames: _draft.hidePatientNames,
      smartOneDayView: _draft.smartOneDayView,
      defaultView: _draft.defaultView,
      weekStartsOn: _draft.weekStartsOn,
      showWeekends: _draft.showWeekends,
      showClosedDayLabel: _draft.showClosedDayLabel,
      condensedHeader: _draft.condensedHeader,
    );
    setState(() => _saving = true);
    try {
      final repo = widget.repo ?? context.read<CalendarDisplaySettingsRepository>();
      await repo.updateSettings(widget.clinicId, updated.toPatchMap());
      if (!mounted) return;
      if (widget.onSaved != null) {
        widget.onSaved!(updated);
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar display settings saved.')),
        );
      } else {
        // Embedded in Settings (no onSaved): stay on screen, show success, refresh draft.
        setState(() {
          _saving = false;
          _draft = updated;
        });
        _syncControllersFromDraft();
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Calendar display settings saved.')),
        );
      }
    } on FirebaseFunctionsException catch (e) {
      if (!mounted) return;
      final msg = e.code == 'permission-denied'
          ? "You don't have permission to change these settings."
          : (e.message ?? e.code);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(msg), backgroundColor: Theme.of(context).colorScheme.errorContainer),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Could not save: ${e.toString().split('\n').first}'),
          backgroundColor: Theme.of(context).colorScheme.errorContainer,
        ),
      );
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _resetToDefaults() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Reset display settings?'),
        content: const Text(
          'This will restore the default calendar display settings for this clinic.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Reset'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() {
      _draft = CalendarDisplaySettings.defaults;
      _syncControllersFromDraft();
    });
    _formKey.currentState?.validate();
  }

  Widget _buildTimeGridCard(double rowGap, ThemeData theme) {
    return SettingsSectionCard(
      title: 'Time grid',
      subtitle: 'Hours and block size shown on the calendar.',
      children: [
        NumberSettingRow(
          label: 'Start hour',
          controller: _startHourController,
          unit: '',
          validator: validateDisplayStartHour,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _draft = _draft.copyWith(displayStartHour: n.clamp(0, 23)));
          },
        ),
        SizedBox(height: rowGap),
        NumberSettingRow(
          label: 'End hour',
          controller: _endHourController,
          unit: '',
          validator: (v) => validateDisplayEndHour(v, int.tryParse(_startHourController.text) ?? 0),
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _draft = _draft.copyWith(displayEndHour: n.clamp(1, 24)));
          },
        ),
        SizedBox(height: rowGap),
        NumberSettingRow(
          label: 'Minutes per block',
          helperText: 'e.g. 5, 10, 15, 20, 30',
          controller: _minutesPerBlockController,
          unit: 'min',
          validator: validateMinutesPerBlock,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _draft = _draft.copyWith(minutesPerBlock: n.clamp(5, 60)));
          },
        ),
        SizedBox(height: rowGap),
        NumberSettingRow(
          label: 'Slot height',
          helperText: 'Pixels per block',
          controller: _slotHeightController,
          unit: 'px',
          validator: validateSlotHeightPx,
          keyboardType: const TextInputType.numberWithOptions(decimal: true),
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[\d.]')),
            LengthLimitingTextInputFormatter(4),
          ],
          onChanged: (v) {
            final n = double.tryParse(v);
            if (n != null) setState(() => _draft = _draft.copyWith(slotHeightPx: n.clamp(16.0, 96.0)));
          },
        ),
        SizedBox(height: rowGap),
        NumberSettingRow(
          label: 'Time picker increment',
          helperText: 'e.g. 5, 10, 15, 30',
          controller: _timePickerIncrementController,
          unit: 'min',
          validator: validateTimePickerIncrement,
          inputFormatters: [
            FilteringTextInputFormatter.digitsOnly,
            LengthLimitingTextInputFormatter(2),
          ],
          onChanged: (v) {
            final n = int.tryParse(v);
            if (n != null) setState(() => _draft = _draft.copyWith(timePickerIncrementMinutes: n.clamp(1, 60)));
          },
        ),
      ],
    );
  }

  Widget _buildSwitchRow(String title, bool value, ValueChanged<bool> onChanged, ThemeData theme, {String? subtitle}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 4),
      child: Row(
        crossAxisAlignment: subtitle != null ? CrossAxisAlignment.start : CrossAxisAlignment.center,
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  title,
                  style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 2),
                  Text(
                    subtitle,
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                      fontSize: 12,
                    ),
                  ),
                ],
              ],
            ),
          ),
          Switch(
            value: value,
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildInteractionCard(ThemeData theme) {
    return SettingsSectionCard(
      title: 'Interaction & indicators',
      children: [
        _buildSwitchRow(
          'Show current time indicator',
          _draft.showCurrentTimeIndicator,
          (v) => setState(() => _draft = _draft.copyWith(showCurrentTimeIndicator: v)),
          theme,
        ),
        const SizedBox(height: 16),
        _buildSwitchRow(
          'Confirm appointment moves',
          _draft.confirmAppointmentMoves,
          (v) => setState(() => _draft = _draft.copyWith(confirmAppointmentMoves: v)),
          theme,
        ),
        const SizedBox(height: 16),
        _buildSwitchRow(
          'Show waitlist matches on cancel',
          _draft.showWaitlistMatchesOnCancel,
          (v) => setState(() => _draft = _draft.copyWith(showWaitlistMatchesOnCancel: v)),
          theme,
        ),
        const SizedBox(height: 16),
        _buildSwitchRow(
          'Show financial indicators on appointments',
          _draft.showFinancialIndicators,
          (v) => setState(() => _draft = _draft.copyWith(showFinancialIndicators: v)),
          theme,
          subtitle: 'Show a payment/billing icon on appointment blocks.',
        ),
      ],
    );
  }

  Widget _buildPrivacyCard(ThemeData theme) {
    return SettingsSectionCard(
      title: 'Privacy',
      children: [
        _buildSwitchRow(
          'Hide patient names',
          _draft.hidePatientNames,
          (v) => setState(() => _draft = _draft.copyWith(hidePatientNames: v)),
          theme,
        ),
      ],
    );
  }

  Widget _buildViewBehaviourCard(ThemeData theme) {
    return SettingsSectionCard(
      title: 'View behaviour',
      children: [
        _buildSwitchRow(
          'Smart 1-day view (hide non-working)',
          _draft.smartOneDayView,
          (v) => setState(() => _draft = _draft.copyWith(smartOneDayView: v)),
          theme,
          subtitle: 'In 1-day view, hide practitioners with no opening hours that day.',
        ),
      ],
    );
  }

  static const _defaultViewOptions = ['day', '3days', 'week', 'month'];
  static const _defaultViewLabels = ['Day', '3 Days', '7 Days', 'Month'];
  static const _weekStartsOptions = ['monday', 'sunday'];
  static const _weekStartsLabels = ['Mon', 'Sun'];

  Widget _buildSegmentRow(
    String label,
    String value,
    List<String> options,
    List<String> labels,
    ValueChanged<String> onChanged,
    ThemeData theme,
  ) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            label,
            style: theme.textTheme.bodyMedium?.copyWith(color: theme.colorScheme.onSurface),
          ),
          const SizedBox(height: 8),
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: List.generate(options.length, (i) {
              final opt = options[i];
              final selected = value == opt;
              return ChoiceChip(
                label: Text(labels[i]),
                selected: selected,
                onSelected: (_) => onChanged(opt),
                selectedColor: theme.colorScheme.primaryContainer,
                labelStyle: theme.textTheme.labelMedium?.copyWith(
                  color: selected ? theme.colorScheme.onPrimaryContainer : theme.colorScheme.onSurface,
                ),
              );
            }),
          ),
        ],
      ),
    );
  }

  Widget _buildLayoutAndViewCard(ThemeData theme) {
    return SettingsSectionCard(
      title: 'Layout & View',
      subtitle: 'Controls the default calendar view and header layout. Doesn\'t change availability.',
      children: [
        _buildSegmentRow(
          'Default view',
          _draft.defaultView,
          _defaultViewOptions,
          _defaultViewLabels,
          (v) => setState(() => _draft = _draft.copyWith(defaultView: v)),
          theme,
        ),
        _buildSegmentRow(
          'Week starts on',
          _draft.weekStartsOn,
          _weekStartsOptions,
          _weekStartsLabels,
          (v) => setState(() => _draft = _draft.copyWith(weekStartsOn: v)),
          theme,
        ),
        _buildSwitchRow(
          'Show weekends',
          _draft.showWeekends,
          (v) => setState(() => _draft = _draft.copyWith(showWeekends: v)),
          theme,
        ),
        const SizedBox(height: 16),
        _buildSwitchRow(
          'Show "Closed" label',
          _draft.showClosedDayLabel,
          (v) => setState(() => _draft = _draft.copyWith(showClosedDayLabel: v)),
          theme,
          subtitle: 'Show "Closed" in multi-day header for closed days.',
        ),
        const SizedBox(height: 16),
        _buildSwitchRow(
          'Condensed header',
          _draft.condensedHeader,
          (v) => setState(() => _draft = _draft.copyWith(condensedHeader: v)),
          theme,
          subtitle: 'Reduces header height for a tighter layout.',
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    const rowGap = 16.0;

    return Scaffold(
      backgroundColor: AppColors.settingsPageBg,
      appBar: AppBar(
        title: Text(
          'Calendar display settings',
          style: theme.textTheme.titleLarge,
        ),
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () => Navigator.of(context).pop(),
        ),
      ),
      body: Form(
        key: _formKey,
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.screenPadding,
                  vertical: AppSpacing.sectionGap,
                ),
                child: Center(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      final isWideViewport = MediaQuery.sizeOf(context).width >= 1100;
                      final maxContentWidth = isWideViewport ? 1100.0 : AppSizes.maxContentWidth;
                      return ConstrainedBox(
                        constraints: BoxConstraints(maxWidth: maxContentWidth),
                        child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Text(
                          _introText,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: theme.colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                            height: 1.4,
                          ),
                        ),
                        const SizedBox(height: 20),

                        // Responsive: 2 columns at ≥1100px viewport; fixed widths for alignment
                        LayoutBuilder(
                          builder: (context, constraints) {
                            const gapBetweenCards = 24.0;
                            const columnGap = 24.0;
                            const fixedColumnWidth = 400.0;
                            final isWide = MediaQuery.sizeOf(context).width >= 1100;

                            if (isWide) {
                              return Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  SizedBox(
                                    width: fixedColumnWidth,
                                    child: _buildTimeGridCard(rowGap, theme),
                                  ),
                                  const SizedBox(width: columnGap),
                                  SizedBox(
                                    width: fixedColumnWidth,
                                    child: Column(
                                      crossAxisAlignment: CrossAxisAlignment.stretch,
                                      children: [
                                        _buildInteractionCard(theme),
                                        const SizedBox(height: gapBetweenCards),
                                        _buildPrivacyCard(theme),
                                        const SizedBox(height: gapBetweenCards),
                                        _buildViewBehaviourCard(theme),
                                        const SizedBox(height: gapBetweenCards),
                                        _buildLayoutAndViewCard(theme),
                                      ],
                                    ),
                                  ),
                                ],
                              );
                            }
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: [
                                _buildTimeGridCard(rowGap, theme),
                                const SizedBox(height: gapBetweenCards),
                                _buildInteractionCard(theme),
                                const SizedBox(height: gapBetweenCards),
                                _buildPrivacyCard(theme),
                                const SizedBox(height: gapBetweenCards),
                                _buildViewBehaviourCard(theme),
                                const SizedBox(height: gapBetweenCards),
                                _buildLayoutAndViewCard(theme),
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  );
                    },
                  ),
                ),
              ),
            ),
            // Sticky bottom Save bar — top border, primary Save when enabled, Reset medium emphasis
            Container(
              decoration: BoxDecoration(
                color: theme.colorScheme.surface,
                border: Border(
                  top: BorderSide(color: AppColors.divider),
                ),
              ),
              child: SafeArea(
                top: false,
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.screenPadding,
                    14,
                    AppSpacing.screenPadding,
                    16,
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      TextButton(
                        onPressed: _saving ? null : _resetToDefaults,
                        style: TextButton.styleFrom(
                          foregroundColor: theme.colorScheme.primary,
                        ),
                        child: Text(
                          'Reset',
                          style: theme.textTheme.labelLarge?.copyWith(
                            fontWeight: FontWeight.w500,
                          ),
                        ),
                      ),
                      FilledButton(
                        onPressed: (_saving || _draftEqualsInitial())
                            ? null
                            : () async {
                                if (!_formKey.currentState!.validate()) return;
                                await _save();
                              },
                        style: FilledButton.styleFrom(
                          backgroundColor: (_saving || _draftEqualsInitial())
                              ? null
                              : theme.colorScheme.primary,
                          foregroundColor: (_saving || _draftEqualsInitial())
                              ? null
                              : theme.colorScheme.onPrimary,
                          minimumSize: const Size(120, AppSizes.buttonHeight),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(AppRadius.element),
                          ),
                        ),
                        child: _saving
                            ? SizedBox(
                                height: 20,
                                width: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: theme.colorScheme.onPrimary,
                                ),
                              )
                            : Text(
                                'Save',
                                style: theme.textTheme.labelLarge?.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
