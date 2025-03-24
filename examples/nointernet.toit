import esp32 show adjust_real_time_clock
import ...ds3231 show Ds3231
import ntp

// Only RTC is available, no wifi. The DS3231 can be off 1-2min/year
// but for many applications this is OK

// The following configurations are for convenience (the pins are in the same order)
// In fact you are free to use any pin is allowed by the board or the ESP chip
// read the board's documentation for the allowed pins
rtc ::= Ds3231 --sda=5 --scl=4 // /* esp32-c3 luatos core (with and without serial chip) */
//ds := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
// TODO devkit
// todo S3 devkit

main:
  // set local time if you wish here
  set-timezone "EET-2EEST,M3.5.0/3,M10.5.0/4"

  task:: update-time
  sleep --ms=1000
  task::
    while true:
      // works with or without internet
      // the Ds3231 must have the time set
      print "The time is $Time.now.local" // UTC time. For local time use Time.now.local
      sleep --ms=5000

update-time:
  while true:
    result := rtc.get
    if result.error: print "Cannot get the RTC time : $result.error"
    else:
      // The Ds3231 is more accurate than the ESP32 board crystal
      // we prefer once per hour to get the time
      adjust_real_time_clock result.adjustment
      print "Got system time from RTC : adjustment=$result.adjustment"
    sleep (Duration --h=1)
