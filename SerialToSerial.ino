#include <Arduino.h>

HardwareSerial GPSSerial(1); 

void setup() {
  Serial.begin(115200); 
  while (!Serial) { delay(10); }
  
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