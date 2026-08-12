class UnitConverter {
  static double metersToFeet(double meters) => meters * 3.28084;
  static double feetToMeters(double feet) => feet / 3.28084;
  static double kmhToMph(double kmh) => kmh / 1.609344;
  static double mphToKmh(double mph) => mph * 1.609344;

  static double celsiusToFahrenheit(double celsius) {
    return (celsius * 9 / 5) + 32;
  }

  static double calculateDensityAltitude(double startAltMeters, double tempC) {
    final isaTemp = 15.0 - 0.0065 * startAltMeters;
    return startAltMeters + 120.0 * (tempC - isaTemp);
  }
}
