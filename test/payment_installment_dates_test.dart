import 'package:flutter_test/flutter_test.dart';
import 'package:untitled1/utils/payment_installment_dates.dart';

void main() {
  test('generates one monthly date for each credit-card installment', () {
    final dates = generateMonthlyInstallmentDates(
      firstDate: DateTime(2026, 8, 4),
      count: 5,
    );

    expect(dates, [
      DateTime(2026, 8, 4),
      DateTime(2026, 9, 4),
      DateTime(2026, 10, 4),
      DateTime(2026, 11, 4),
      DateTime(2026, 12, 4),
    ]);
  });

  test('anchors month-end installments to the original day', () {
    final dates = generateMonthlyInstallmentDates(
      firstDate: DateTime(2026, 1, 31),
      count: 3,
    );

    expect(dates, [
      DateTime(2026, 1, 31),
      DateTime(2026, 2, 28),
      DateTime(2026, 3, 31),
    ]);
  });
}
