import esp32 show adjust_real_time_clock
import ds3231 show Ds3231
import ntp

// we have both wifi and DS3231 and we want the RTC
// for the periods the WIFI is anavailable

/*
If the bus is shared between more than one i2c devices we need to create the bus ourselves
bus := i2c.Bus --sda=(gpio.Pin 25) --scl=(gpio.Pin 26)
device := bus.device ds3231.DEFAULT-I2C
rtc := ds3231 device

You can use GPIO pins as GND and VCC (only 4mA)
This is useful for easy cabling and battery powered projects

gnd := gpio.Pin 32 --output --value=0
vcc := gpio.Pin 33 --output --value=1

If the clock is the only device in the bus, all the above
setup can be simplified with the following constructor
if you are using hardware VCC and GND leave the --vcc and --gnd out.
*/


/*
The following configurations are for convenience (the pins are in the same order)
you are free to use any pin that is allowed by the board or the ESP chip.
Read the board's documentation on the pins you can use. Straping and special purpose pins
should be avoided.
*/
// rtc ::= Ds3231 --scl=4 --sda=5 // /* esp32-c3 luatos core (with and without serial chip) */
// rtc ::= Ds3231 --scl=7 --sda=6 --vcc=10 --gnd=3 /* esp32-c3 core with GPIO as vcc and gnd */
// rtc := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
rtc := Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26 /* ESP32 Devkit all versions */
// rtc := Ds3231 --sda=35 --scl=36 --vcc=37 --gnd=38 /* S3 devkitC abudance of pins here */

main:
  task:: update-time // This task is doing the time sync
  task:: check-time-sync // for debugging
  //task:: check-get-set-accuracy // for debugging
  //task :: my-project

// This task is using the most appropriate time source :
// If internet is working, it uses NTP (and updates the RTC),
// and when NTP is not available, it uses DS3231 as a backup
update-time:
  last-ntp-time/Time? := null
  // The RTC is available before Wifi+NTP and sets the time first
  rtc-result := rtc.get
  if rtc-result.adjustment:
    now := Time.now + rtc-result.adjustment
    adjust_real_time_clock rtc-result.adjustment
    print "Got system time from RTC : $now"
  else:
    print "Cannot get the RTC time : $rtc-result.error"
  while true:
    ntp-result := ntp.synchronize // --max-rtt=(Duration --ms=500)  --server="pool.ntp.org"
    if ntp-result:
      if last-ntp-time != null:
        if ntp-result.accuracy > (Duration --ms=100):
          print "The accuracy is bad, bypassing the measurement"
          sleep (Duration --m=1)
          continue
      last-ntp-time = Time.now +ntp-result.adjustment
      // the adjustment is relative to the current time
      // WARNING : we first set the RTC clock, so the adjustment will be valid
      err := rtc.set --adjustment=ntp-result.adjustment
      // Now we can also set the system time, which of course resets the required adjustment
      adjust_real_time_clock ntp-result.adjustment // The time will be corrected gradually
      // set-real-time-clock Time.now + ntp-result.adjustment // the same but sets the time instantly
      if err: print "Cannot set the RTC time : err"
      else: print "Setting the RTC time using the NTP time"
      print "NTP sync done adjustment=$ntp-result.adjustment acc=$ntp-result.accuracy"
      //
      sleep (Duration --m=30) // sync again after 30 min
    else:
      print "NTP synchronization failed" // comment out if the wifi is intermittent
      sleep (Duration --m=1) // we will try again in 1 min.

check-time-sync: // for debugging purposes
  sleep --ms=5000
  print "Do not use this for working projects, tries to demonstrate the system clock drift and the DS3231 clock drift, which is minimal and hardly measurable with this test, unless you leave running for at least a day."
  while true:
    ntp-result := ntp.synchronize // --server="your local server IP but usually not needed"
    if ntp-result:
      print "[TEST-START] NTP-time - System-time : $ntp-result.adjustment accuracy=$ntp-result.accuracy"
    rtc-result := rtc.get
    if rtc-result.adjustment:
      print "[TEST      ] RTC-time - System-time : $rtc-result.adjustment. Possible RTC drift : $rtc.expected-drift"
      if ntp-result:
        print "[TEST-END  ] NTP-time - RTC-time    : $(ntp-result.adjustment - rtc-result.adjustment)"
    else:
      print "Cannot get the time from the RTC : $rtc-result.error"
    sleep --ms=30_000

check-get-set-accuracy:
  sleep --ms=5000
  print "Do not use this for working projects, it sets and gets back the time from the RTC to demonstrate how accurate the set/get functions are"
  while true:
    print "We set the RTC time $Time.now"
    rtc.set --adjustment=(Duration 0)
    sleep --ms = 1500
    print "We get it aggain"
    adjustment := rtc.get
    print "Difference is $adjustment"
    sleep --ms=4500
