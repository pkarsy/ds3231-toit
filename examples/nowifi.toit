import esp32 show adjust_real_time_clock
import ds3231 show Ds3231

// Only RTC is available, no wifi. The DS3231 can be off 1min/year
// but for many applications this is OK.
// If there is Wifi, even rarelly your mobile phone as hotspot
// you should check the "ntpplusrtc.toit" example.

// The following configurations are for convenience (the pins are in the same order)
// you are free to use any pin that is allowed by the board or the ESP chip.
// Read the board's documentation on the pins you can use. Straping and special purpose pins
// should be avoided
rtc ::= Ds3231 --scl=4 --sda=5 // /* esp32-c3 luatos core (with or without serial chip) */
// rtc ::= Ds3231 --scl=7 --sda=6 --vcc=10 --gnd=3 /* esp32-c3 core with GPIO as vcc and gnd */
// rtc := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
// rtc := Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26 /* ESP32 Devkit all versions */
// rtc := Ds3231 --sda=35 --scl=36 --vcc=37 --gnd=38 /* S3 devkitC, abudance of pins here */

main:
  // set-timezone "EET-2EEST,M3.5.0/3,M10.5.0/4"
  task:: update-system-time
  sleep --ms=1_000 // wait a while, so the main-job finds correct time
  task:: main-job


main-job: // Does not return, and should typically called inside a task.
  while true:
    // Works with or without internet. Of course the DS3231 must have correct
    // time (and a good CR2032 coin cell). See the other example.
    print "The time is $Time.now" // UTC time. For local time use Time.now.local.
    sleep --ms=5_000


update-system-time: // Does not return, and should typically called inside a task.
  while true:
    adjustment := rtc.get
    // The Ds3231 crystal is way more accurate than the crystal on the ESP32 board
    // and also is temperature compensated.
    adjust_real_time_clock adjustment
    print "Got system time from RTC : adjustment=$adjustment"
    //else:
    //  print "Cannot get the RTC time : $result.error"
    sleep (Duration --h=1)
