import esp32 show adjust_real_time_clock
import ds3231 show Ds3231
import ntp

/*
Scenario:
we have both wifi and DS3231 and we want the RTC
for the periods the WIFI is anavailable

If the bus is shared between more than one i2c devices we need to create the bus ourselves
bus := i2c.Bus --sda=(gpio.Pin 25) --scl=(gpio.Pin 26)
device := bus.device ds3231.I2C-DEFAULT
rtc := ds3231 device

You can use GPIO pins as GND and VCC (only 4mA)
This is useful for easy cabling, and for battery powered projects (the ESP32 sleep turns off the DS3231)

gnd := gpio.Pin 32 --output --value=0
vcc := gpio.Pin 33 --output --value=1

If the clock is the only device in the bus, all the above
setup can be simplified with the following constructor
if you are true hardware VCC and GND pins, leave the --vcc and --gnd out.

The following configurations are for convenience (the pins are in the same order)
you are free to use any pin that is allowed by the board or the ESP chip.
Read the board's documentation on the pins you can use. Straping and special purpose pins
should be avoided.

// rtc ::= Ds3231 --scl=7 --sda=6 --vcc=10 --gnd=3 /* esp32-c3 core with GPIO as vcc and gnd */
// rtc := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
// rtc := Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26 /* ESP32 Devkit all versions */
// rtc := Ds3231 --sda=35 --scl=36 --vcc=37 --gnd=38 /* S3 devkitC abudance of pins here */

*/
rtc ::= Ds3231 --scl=4 --sda=5 /* esp32-c3 luatos core (with or without serial chip) */

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
  if true:
    // The RTC is available before Wifi+NTP and sets the time first
    adjustment := rtc.get
    //if rtc-result.adjustment:
    now := Time.now + adjustment
    adjust_real_time_clock adjustment
    print "Got system time from RTC : $now"
    //else:
    //  print "Cannot get the RTC time : $rtc-result.error"
  while true:
    result := ntp.synchronize // --max-rtt=(Duration --ms=500)  --server="pool.ntp.org"
    if result:
      if last-ntp-time != null:
        if result.accuracy > (Duration --ms=100):
          print "The accuracy is bad, bypassing the measurement"
          sleep (Duration --m=1)
          continue
      last-ntp-time = Time.now + result.adjustment
      rtc.set result.adjustment //--adjustment=result.adjustment
      adjust_real_time_clock result.adjustment // The time will be corrected gradually
      print "Setting the RTC time using the NTP time"
      print "NTP sync done adjustment=$result.adjustment acc=$result.accuracy"
      sleep (Duration --m=30) // sync again after 30 min
    else:
      print "NTP synchronization failed" // comment out if the wifi is intermittent
      sleep (Duration --m=1) // we will try again in 1 min.

check-time-sync: // for debugging purposes
  sleep --ms=5000
  print "\n\n\nDo not use this for working projects, tries to demonstrate the system clock drift(significant) and the DS3231 clock drift, which is minimal and hardly measurable with this test, unless you leave it running for at least a day.\n\n\n"
  while true:
    ntp-result := ntp.synchronize // --server="your local server IP but usually not needed"
    if ntp-result:
      print "[TEST-START] NTP-time - System-time : $ntp-result.adjustment accuracy=$ntp-result.accuracy"
    adjustment := rtc.get
    print "[TEST      ] RTC-time - System-time : $adjustment. Possible RTC drift : $rtc.expected-drift"
    if ntp-result:
      print "[TEST-END  ] NTP-time - RTC-time    : $(ntp-result.adjustment - adjustment)"
    sleep --ms=30_000

check-get-set-accuracy:
  sleep --ms=5000
  print "\n\n\nDo not use this for working projects, it sets and gets back the time from the RTC to demonstrate how accurate the set/get functions are.\n\n\n"
  while true:
    print "We set the RTC time $Time.now"
    rtc.set (Duration 0)
    sleep --ms = 1500
    print "We get it aggain"
    adjustment := rtc.get
    print "Difference is $adjustment"
    sleep --ms=4500
