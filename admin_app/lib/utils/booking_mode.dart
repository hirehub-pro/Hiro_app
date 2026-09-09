const String bookingModeCustomerTravels = 'customer_travels';
const String bookingModeProviderTravels = 'provider_travels';
const String bookingModeOnline = 'online';

String normalizeBookingMode(String? value) {
  switch ((value ?? '').trim().toLowerCase()) {
    case bookingModeCustomerTravels:
      return bookingModeCustomerTravels;
    case bookingModeOnline:
      return bookingModeOnline;
    case bookingModeProviderTravels:
    default:
      return bookingModeProviderTravels;
  }
}

bool isCustomerTravelBookingMode(String? value) {
  return normalizeBookingMode(value) == bookingModeCustomerTravels;
}
