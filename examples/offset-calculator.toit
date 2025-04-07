import esp32 show adjust_real_time_clock set-real-time-clock deep-sleep
import ds3231 show Ds3231
import gpio

import ntp
import mqtt
import net
import encoding.json show encode

/*
DS3231 aging offset calculator.
Only a ESP32x (with stable wifi) and DS3231 is needed. ESP modules with lipo socket are
greatly preferred (To avoid interruptions).
The extreme simplicity has the drawback of slowness.
Typically after after 12-24 h the program applies an aging factor. However the program must
run again as rarely the correction eliminates the systematic drift entirelly. After a few days
the process is complete. The good news is you can have many ESP modules running in parallel.
YOU NEED TO PUT A LABEL WITH THE TOIT name in every ESP module is used for this purpose.


The accuracy of DS3231 is (even without using aging offset) so high,
that we need to leave the program running for at least a day to be
able to find a relativelly clear difference between RTC and NTP

The program sends messages to mqtt so you need the serial port
only for flashing the ToitVirtualMachine. After that use a USB charger
upload the code as a container and when a day or 2 passes, see the progress.
Do not restart/power off the module in this period. (This is why the Lipo socket is useful)

Many DS3231 modules have ppm far lower than 2ppm even close to 0 ppm
at room conditions. Some values I found are 1.2 0.6 0.2 etc

Use the SN chips. The MEMS based are not very accurate

Try to mimic somewhat the expected working temperature conditions.

*/

/** START OF CONFIGURATION */

/*
Use a (good) LAN NTP server if you have one
I use "chrony" on a debian server mini pc (ethernet connection of course).
Many sources report it as one of the best NTP servers. The buildin NTP
server of openwrt does not seem to have millisecond accuracy which is
logical (I am not blaming openwrt here) and should not be used. If your
Internet connection is not stable, no server can help you.
*/
NTP-SERVER ::= "10.5.2.3"

/*
Works but it is suboptimal. The ntp error is more than 15ms
(depends on your location) and accasionally 200-500ms !
Needless to say, you need more time to get acceptable results (even 2 days).
On the other hand if you dont have a quality local NTP server better use
this one.
*/
// NTP-SERVER ::= "pool.ntp.org"

/**
For pool.ntp.org can be 20ms.
You can reduce this if you have a LAN ntp server :
works with --ms=7 with ESP32-C3
and --ms=8-10 with ESP32 (using local chrony)
esp32-c3 although the cheapest in the family, has superb wifi lag(low)
*/
NTP-ERROR-MAX := (Duration --ms=10)
/**
You can reduce it a little further to have as much accuracy as you can, when
setting the time to the DS3231 (when the program starts). The first NTP
mesurement is the most important, as it affects the accuracy of the whole
experiment. If unsure leave it as is.
*/
NTP-ERROR-MAX-SETUP := NTP-ERROR-MAX

//* The time duration between checks. There is no point to reduce it. */
CHECK-PERIOD ::= (Duration --m=30)

/** See the example "ntp-plus-rtc.toit" for various examples on pinout setup */
//rtc ::= Ds3231 --scl=4 --sda=5 // /* esp32-c3 luatos core (with and without serial chip)
// ESP32 Devkit+lolin32 [lite]
rtc := Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26
// WARNING when vcc or gnd are GPIO pins some minimal time probably
// is needed for the module to communicate via i2c

/**
The MQTT client object. You can use a private TLS server of course.
but this one works out of the box.
*/
client/mqtt.SimpleClient? := null
HOST ::= "test.mosquitto.org"
PORT ::= 1883

/** Your initials or something unique, mainly useful for public mqtt servers.
Set it once and do not change it again. Appears as part of the mqtt topic
and isolates you from possible other users. */
ID ::= "pk"

// should be the TOIT device name as created by "jag"
// and writen to the module with a sticker or similar
TOIT-NAME ::= "L4"

// If you want the reports in local time, put the apropriate value here
//TIMEZONE ::= null // for UTC
TIMEZONE ::= "EET-2EEST,M3.5.0/3,M10.5.0/4"

// You perhaps want to have the led ON to always be sure the module is powered.
// Otherwise leave the values as null
LED-PIN/int? ::= 22 // The pin with the LED, otherwise null
LED-VALUE/int? ::= 0 // 1(active high) 0(active low) or null(no led)

/** END OF CONFIGURATION */

TOPIC ::= "toit/ds3231-$ID/aging-offset-$TOIT-NAME"

main:
  if TIMEZONE != null:
    set-timezone TIMEZONE
  if LED-PIN and LED-VALUE:
    p ::= gpio.Pin LED-PIN --output
    p.set LED-VALUE
  /** sets the system+RTC time from NTP, and return how accurate
  the measurement was */
  rtc-write-accuracy ::= prepare-system
  /** Connects to mqtt */
  mqtt-setup
  calulate-drift rtc-write-accuracy

mqtt-setup:
  while true:
    err := catch :
      if client: client.close
      transport := mqtt.TcpTransport --host=HOST --port=PORT
      c := mqtt.SimpleClient --transport=transport
      options := mqtt.SessionOptions --client-id="offset-$(random)"
      c.start --options=options
      // At this point the client is connected to the broker.
      print "Connected to $HOST:$PORT and will publish results to $TOPIC"
      client = c
      return
    if err:
      print "Cannot connect to broker : err = $err"
    sleep --ms=15_000
  
mqtt-pub payload/string:
  if client==null:
    print "Cannot send to mqtt, not connected."
    return
  err := catch:
    client.publish TOPIC payload //--retain
  if err:
    print "Cannot publish : err = $err"
    mqtt-setup

// Sets the system time from NTP and writes to the RTC
prepare-system -> Duration:
  sleep --ms=1000 // to leave time to DS3231 to power up if vcc/gnd are GPIOs
  while true:
    result := ntp.synchronize --server=NTP-SERVER
    if result:
      if result.accuracy < NTP-ERROR-MAX-SETUP:
        rtcadj ::= rtc.get
        timediff := result.adjustment - rtcadj
        rtc.set result.adjustment
        adjust_real_time_clock result.adjustment // The time will be corrected gradually
        print "\nNTP sync done, adjustment=$result.adjustment accuracy=$result.accuracy"
        return result.accuracy
        break
      else:
        print "The accuracy of ntp is bad : $result.accuracy"
        // you can commenet the next 2 lines if you are sure the toleance is OK
        print "Increasing the error tolerance my 1ms"
        NTP-ERROR-MAX-SETUP=NTP-ERROR-MAX-SETUP+(Duration --ms=1)
    else:
      print "NTP synchronization failed"
    sleep --ms=5000
  
calulate-drift setup-accuracy:
  start-time := Time.now
  sleep --ms=5000
  aging-offset ::= rtc.get-aging-offset
  while true:
    result := ntp.synchronize --server=NTP-SERVER
    if result:
      if result.accuracy < NTP-ERROR-MAX:
        rtcadj ::= rtc.get
        diff ::= rtcadj - result.adjustment
        time-passed ::= start-time.to Time.now
        ppm ::= 1.0*1e6*diff.in-us/time-passed.in-us
        ppm-error ::= 1.0*1e6*(result.accuracy.in-us+setup-accuracy.in-us)/time-passed.in-us
        //print "$diff.in-us $time-passed.in-us $result.accuracy.in-us $time-passed.in-us"
        offs:= (ppm*10+0.5).to-int
        //suggested-offset ::= ?
        //if (ppm-error>0.2) or (ppm-error>0.7*ppm):
        //  suggested-offset="\"-\""
        //else:
        //  suggested-offset= "$(offs+aging-offset)"
        now ::= Time.now + result.adjustment
        /* verdict/string ::= ?
        if ppm-error>1:
          verdict = "INVALID"
        else if ppm-error>0.2:
          verdict = "LOW-ACCURACY"
        else:
          verdict = "VALID" */
        loctime ::= now.local.stringify[..19]
        runtime ::= start-time.to now
        next-measuremet ::= (now+CHECK-PERIOD).local.stringify[..19]
        msg := """{
          "TimeNow":"$loctime",
          "Runtime (hours)":$runtime.in-h,
          "Next Measurement (approx)":"$next-measuremet",
          "DS3231 SetupTime accuracy (ms)":$(setup-accuracy.in-ms),
          "NTP accuracy (ms)":$(result.accuracy.in-ms),
          "Time Keeping Accuracy (ppm)":$(%0.1f ppm),
          "Accuracy Uncertainty (ppm)": $(%0.1f ppm-error),
          "IP-address":"$net.open.address",
          "Stored Aging Offset":$aging-offset,
          "Toit Name/Label":"$TOIT-NAME"
        }"""
        print msg
        mqtt-pub msg

        if ppm.abs*2<ppm-error and ppm.abs>0.1:
          write-offset := offs+aging-offset
          rtc.set-aging-offset write-offset
          deep-sleep
            Duration --s=10 // restart the module
        sleep CHECK-PERIOD
      else:
        print "Bad NTP accuracy : $result.accuracy"
        // we want a result, so we retry soon
        sleep (Duration --s=10)
    else:
      print "NTP synchronization failed"
      sleep (Duration --s=10)
