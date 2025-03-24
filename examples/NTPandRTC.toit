import esp32 show adjust_real_time_clock
import ...ds3231 show Ds3231
import ntp

// we have both wifi and DS3231 and we want the RTC
// for the periods the WIFI is anavailable

ds := Ds3231 --sda=5 --scl=4 // /* esp32-c3 luatos core */
//ds := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
// TODO devkit
// todo S3 devkit

main:
  task:: update-time
  task:: check-time-sync

update-time:
  /*
    we can use GPIO pins as GND and VCC if we use the DS3231 alone (only 4mA)
    gnd := gpio.Pin 32 --output --value=0
    vcc := gpio.Pin 33 --output --value=1
  */

  /*
    If the bus is shared between more than one i2c devices we need to create the bus ourselves
    bus := i2c.Bus --sda=(gpio.Pin 25) --scl=(gpio.Pin 26)
    device := bus.device ds3231.DEFAULT-I2C
    ds := ds3231 device
  */

  /*
    If the clock is the only device in the bus, all the above
    setup can be simplified with this constructor
    if you are using hardware VCC and GND leave the --vcc and --gnd out.
  */
  //ds := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32 /* Lolin32 lite */
  //ds := Ds3231 --sda=5 --scl=4 // --vcc=33 --gnd=32 /* esp32-c3 luatos core */
  if true: // This happens on boot
    // The RTC is avoailable before the NTP and sets the time first
    rtc-result := ds.get
    // the result cannot be null (unlike the ntp) so we check result.error instead of result
    if rtc-result.error: print "Cannot get the RTC time : $rtc-result.error"
    else:
      adjust_real_time_clock rtc-result.adjustment
      print "Got system time from RTC : adjustment=$rtc-result.adjustment"
  while true:
    ntp-result := ntp.synchronize --max-rtt=(Duration --ms=100) // -server="gr.pool.ntp.org" 
    if ntp-result:
      now:=Time.now
      adjust_real_time_clock ntp-result.adjustment // may need some time (background) to fix the time
      err/string? := ds.set now+ntp-result.adjustment // we do not use Time.now, see last comment
      // this block is printed with up to 1sec delay due to Ds3231.set function
      // we wanted to do the real job before printing
      print "NTP sync done adj=$ntp-result.adjustment acc=$ntp-result.accuracy"
      if err: print err
      else: print "Setting the RTC time using the system time"
      //
      sleep --ms=1_800_000 // sync again in half an hour
    else:
      print "NTP synchronization failed" // comment out if the wifi is intermittent
      sleep --ms=60_000 // we will try again in 1 min. Increase for intermittent wifi

check-time-sync: // for debugging purposes
  sleep --ms=5000
  while true:
    ntp-result := ntp.synchronize --server="gr.pool.ntp.org"
    if ntp-result:
      print "[TEST-START] NTP-time - System-time : $ntp-result.adjustment accuracy=$ntp-result.accuracy"
    rtc-result := ds.get
    if not rtc-result.error:
      print "[TEST      ] RTC-time - System-time : $rtc-result.adjustment"
    if (not rtc-result.error) and (ntp-result):
      print "[TEST-END  ] NTP-time - RTC-time    : $(ntp-result.adjustment - rtc-result.adjustment)"
    sleep --ms=30_000
