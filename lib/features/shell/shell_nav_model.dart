// lib/features/shell/shell_nav_model.dart
// ClinicianTab enum and shell nav items for sidebar/bottom nav.

import 'package:flutter/material.dart';

enum ClinicianTab {
  calendar,
  patients,
  preassess,
  exercises,
  invoices,
  paymentQr,
  settings,
  publicPortal,
}

class ShellNavItem {
  const ShellNavItem({
    required this.tab,
    required this.label,
    required this.icon,
    required this.group,
  });
  final ClinicianTab tab;
  final String label;
  final IconData icon;
  final String group; // 'Primary' | 'Finance' | 'Admin'
}

const List<ShellNavItem> shellNavItems = [
  ShellNavItem(tab: ClinicianTab.calendar, label: 'Booking Calendar', icon: Icons.calendar_today, group: 'Primary'),
  ShellNavItem(tab: ClinicianTab.patients, label: 'Patients', icon: Icons.people, group: 'Primary'),
  ShellNavItem(tab: ClinicianTab.preassess, label: 'Pre-Assessments', icon: Icons.assignment, group: 'Primary'),
  ShellNavItem(tab: ClinicianTab.exercises, label: 'Exercises', icon: Icons.fitness_center, group: 'Primary'),
  ShellNavItem(tab: ClinicianTab.invoices, label: 'Accounts', icon: Icons.request_quote, group: 'Finance'),
  ShellNavItem(tab: ClinicianTab.paymentQr, label: 'Payment QR', icon: Icons.qr_code_2, group: 'Finance'),
  ShellNavItem(tab: ClinicianTab.settings, label: 'Clinic Settings', icon: Icons.settings, group: 'Admin'),
  ShellNavItem(tab: ClinicianTab.publicPortal, label: 'Public Portal', icon: Icons.public, group: 'Admin'),
];

Map<String, List<ShellNavItem>> groupNavItems(List<ShellNavItem> items) {
  final map = <String, List<ShellNavItem>>{};
  for (final item in items) {
    map.putIfAbsent(item.group, () => []).add(item);
  }
  return map;
}
