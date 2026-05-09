import 'package:flutter/material.dart';

String formatDateOfBirth(DateTime date) {
  final month = date.month.toString().padLeft(2, '0');
  final day = date.day.toString().padLeft(2, '0');
  return '${date.year}-$month-$day';
}

String? validateDateOfBirth(DateTime? date, {DateTime? now}) {
  if (date == null) {
    return 'Required';
  }
  final today = DateUtils.dateOnly(now ?? DateTime.now());
  final selected = DateUtils.dateOnly(date);
  if (selected.isAfter(today)) {
    return 'DOB cannot be in the future';
  }
  if (selected.year < 1900) {
    return 'DOB is too old';
  }
  return null;
}
