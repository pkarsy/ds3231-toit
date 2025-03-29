import esp32 show adjust_real_time_clock set-real-time-clock
import ...ds3231 show Ds3231
import ntp

// we have both wifi and DS3231 and we want the RTC
// for the periods the WIFI is anavailable

/*
  If the bus is shared between more than one i2c devices we need to create the bus ourselves
  bus := i2c.Bus --sda=(gpio.Pin 25) --scl=(gpio.Pin 26)
  device := bus.device ds3231.DEFAULT-I2C
  rtc := ds3231 device
  //
  // we can use GPIO pins as GND and VCC if we use the DS3231 alone (only 4mA)
  gnd := gpio.Pin 32 --output --value=0
  vcc := gpio.Pin 33 --output --value=1
  //
  If the clock is the only device in the bus, all the above
  setup can be simplified with the following constructor
  if you are using hardware VCC and GND leave the --vcc and --gnd out.
*/
rtc := Ds3231 --scl=4 --sda=5  /* esp32-c3 luatos core */
// rtc := Ds3231 --scl=32 --sda=33 --vcc=25 --gnd=26 /* Devkit all versions and some other boards */

main:
  task:: update-time // you can use this task for your project
  task:: check-time-sync // for debugging
  //task:: check-get-set-accuracy // for debugging

// This task is using the most appropriate time source :
// If internet is working, it uses NTP (and updates the RTC),
// and when NTP is not available, it uses DS3231 as a backup
update-time:
  last-ntp-time/Time? := null
  // The RTC is available before Wifi+NTP and sets the time first
  rtc-adjustment := rtc.get
  if not rtc-adjustment: print "Cannot get the RTC time : $rtc.error"
  else:
    now := Time.now + rtc-adjustment
    adjust_real_time_clock rtc-adjustment
    // set-real-time-clock Time.now + rtc-adjustment
    print "Got system time from RTC : $now"
  while true:
    ntp-result := ntp.synchronize // --max-rtt=(Duration --ms=500)  --server="pool.ntp.org"
    if ntp-result:
      if last-ntp-time != null:
        if ntp-result.accuracy > (Duration --ms=100):
          print "The accuracy is bad, bypassing the measurement"
          sleep --ms=60_000
          continue
      last-ntp-time = Time.now +ntp-result.adjustment
      // the adjustment is relative to the current time
      // WARNING : we first set the RTC clock, so the adjustment will be valid
      err/string? := rtc.set --adjustment=ntp-result.adjustment
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
  while true:
    ntp-result := ntp.synchronize --server="10.5.2.2"
    if ntp-result:
      print "[TEST-START] NTP-time - System-time : $ntp-result.adjustment accuracy=$ntp-result.accuracy"
    rtc-adjustment := rtc.get
    if rtc-adjustment:
      print "[TEST      ] RTC-time - System-time : $rtc-adjustment. Calculated RTC drift : $rtc.drift"
      if ntp-result:
        print "[TEST-END  ] NTP-time - RTC-time    : $(ntp-result.adjustment - rtc-adjustment)"
    else:
      print "Cannot get the time from the RTC : $rtc.error"
    sleep --ms=30_000

check-get-set-accuracy:
  sleep --ms=5000
  print "#############"
  while true:
    print "We set the RTC time $Time.now"
    rtc.set --adjustment=(Duration 0)
    sleep --ms = 1500
    print "We get it aggain"
    adjustment := rtc.get
    print "Difference is $adjustment"
    sleep --ms=4500
