bool isValidIsraeliId(String value) {
  final digits = value.trim();
  if (!RegExp(r'^\d{9}$').hasMatch(digits)) return false;

  var sum = 0;
  for (var i = 0; i < digits.length; i++) {
    var product = int.parse(digits[i]) * ((i % 2) + 1);
    if (product > 9) product -= 9;
    sum += product;
  }

  return sum % 10 == 0;
}
