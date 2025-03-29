import esp32 show adjust_real_time_clock
import ...ds3231 show Ds3231

// Only RTC is available, no wifi. The DS3231 can be off 1min/year
// but for many applications this is OK.
// If there is Wifi, even rarelly your mobile phone as hotspot
// you should check the "ntpplusrtc.toit" example.

// The following configurations are for convenience (the pins are in the same order)
// you are free to use any pin that is allowed by the board or the ESP chip.
// Read the board's documentation on the pins you can use. Straping and special purpose pins
// should be avoided
rtc ::= Ds3231 --sda=5 --scl=4 // /* esp32-c3 luatos core (with and without serial chip) */
// rtc := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
// rtc := Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26 /* ESP32 Devkit all versions */
// rtc := Ds3231 --sda=35 --scl=36 --vcc=37 --gnd=38 /* S3 devkitC abudance of pins here */

main:
  // set-timezone "EET-2EEST,M3.5.0/3,M10.5.0/4"
  task:: update-system-time
  sleep --ms=1_000 // we wait a while, so the main-job finds correct time
  task:: main-job


main-job: // does not return, we need to call it with task::
  while true:
    // works with or without internet. Of course the DS3231 must have correct
    // time (and a good CR2032 coin cell). Use the other example to do this
    print "The time is $Time.now" // UTC time. For local time use Time.now.local
    sleep --ms=5_000


update-system-time: // does not return, we need to call it with task::
  while true:
    adjustment := rtc.get
    if adjustment:
      // The Ds3231 crystal is way more accurate than the crystal on the ESP32 board
      // and also is temperature compensated.
      // So is better once per hour to refresh the system time
      adjust_real_time_clock adjustment
      print "Got system time from RTC : adjustment=$adjustment"
    else:
      print "Cannot get the RTC time : $rtc.error"
    sleep (Duration --h=1)
