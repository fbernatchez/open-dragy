#include <Arduino.h>

HardwareSerial GPSSerial(1); 

void setup() {
  Serial.begin(115200); 
  while (!Serial) { delay(10); }
  
  // If you are configuring a factory-new GPS module, change this to 38400 first.
  // After upgrading the GPS to 115200 via u-center 2, change it back to 115200 and re-flash.
  GPSSerial.begin(115200, SERIAL_8N1, 4, 5); 
}

void loop() {
  while (GPSSerial.available() > 0) {
    Serial.write(GPSSerial.read());
  }

  while (Serial.available() > 0) {
    GPSSerial.write(Serial.read());
  }
}