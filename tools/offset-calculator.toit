import esp32 show adjust_real_time_clock set-real-time-clock deep-sleep
import ds3231 show Ds3231
import gpio

import ntp
import mqtt
import net
import encoding.json show encode

/*
WARNING: To use this program effectively you have to check the comments
and set the parameters apropriatelly.
You need an MQTT client like EMQTX or MQTT-Explorer 

Automatically applies the offset to the module. Be aware
that if you remove the battery (and the VCC-GND are unpowered)
the chips loses all settings.

Only a ESP32x (with stable wifi) and DS3231 is needed. ESP modules with lipo socket are
greatly preferred (To avoid interruptions).
Typically after after 12-24 h the program applies an aging factor. However the program must
run again, as rarely the correction eliminates the systematic drift entirelly. After the
aging factor is applied the module will reset and start again.
After a few days the process is complete. The good news is you can have many ESP modules
running in parallel. If you have more than one running modules,
YOU NEED TO PUT A LABEL WITH THE TOIT name in every ESP module is used for this purpose.
The MQTT topic contains the IP and it is very easy with "toit scan" to find the correct
module.

Some values I found are 1.2 0.6 0.2 etc

Use the SN chips. The MEMS based are not very accurate

*/

/** ****** START OF CONFIGURATION ****** */

/** Your initials or something unique, mainly useful for public mqtt servers.
Set it only once, and do not change it again. Appears as part of the mqtt topic
and isolates you from possible other users. */
ID ::= "xy"

/*
Use a (good) LAN NTP server if you have one
I use "chrony" on a debian server mini pc (has ethernet connection).
The buildin NTP server of openwrt does not seem to have millisecond
accuracy which is logical (I am not blaming openwrt here) and should
not be used. The chrony is available for openwrt but I have not tested
it. If your Internet connection is not stable, no server can help.
*/
//NTP-SERVER ::= "192.168.5.2"

/*
Works but it is suboptimal. The ntp error is more than 15ms
(depends on your location) and occasionally 200-500ms !
Needless to say, more time is required to get acceptable results.
*/
NTP-SERVER ::= "pool.ntp.org"

/**
For "pool.ntp.org" cannot be lower than 20ms.
When using a local NTP server(chrony), you can reduce this: 
--ms=7 with ESP32-C3
and --ms=8-10 with ESP32
esp32-c3 although the cheapest in the family, has superb wifi lag(low)
However I still prefer ESP32 lolin32 due to Lipo socket. The measurement
is very lengthly, and the Lipo prevents accidental interruptions. I guess
if you use a power bank (connected to AC) you can use any module.
*/
NTP-ERROR-MAX := (Duration --ms=20) // Reduce to 10 for local chrony
/**
You can reduce it a little further, to have better accuracy, when
setting the time to the DS3231 (when the program starts). The first NTP
measurement is the most important (writes the time to RTC), as it affects
the accuracy of the whole experiment. If unsure leave it as is.
NTP-ERROR-MAX-SETUP := NTP-ERROR-MAX - (Duration --ms=2)
*/
NTP-ERROR-MAX-SETUP := NTP-ERROR-MAX

//* The time duration between checks. There is no reason to reduce it */
CHECK-PERIOD ::= (Duration --m=30)

/** See the example "ntp-plus-rtc.toit" for various pinout setups */
// rtc ::= Ds3231 --scl=4 --sda=5 // esp32-c3 luatos core
// for ESP32 Devkit and lolin32/lite the following is convenent.
rtc :=  Ds3231 --sda=33 --scl=32 --vcc=25 --gnd=26

/**
The MQTT client object. You can use a private server of course.
This one works out of the box, and the truth is, we do not store any
top secret info here.
*/
HOST ::= "test.mosquitto.org"
PORT ::= 1883
client/mqtt.SimpleClient? := null // main->mqtt-setup does the connection

// If you want the reports in local time, put the apropriate value here
// TIMEZONE ::= "EET-2EEST,M3.5.0/3,M10.5.0/4"
TIMEZONE ::= null // for UTC

/** You may want the buldin led to be ON :
- to be sure that the module is powered.
- if the led turns off, to know something happened
Otherwise leave the values as null */
//LED-PIN/int? ::= 22 // The pin with the LED, otherwise null
//LED-VALUE/int? ::= 0 // 1(active high) 0(active low) or null(no led)
LED-PIN/int? ::= null
LED-VALUE/int? ::= null

/** END OF CONFIGURATION */

TOPIC ::= "rtc/ds3231-$ID/aging-offset-$net.open.address"

main:
  if TIMEZONE != null:
    set-timezone TIMEZONE
  if LED-PIN and LED-VALUE:
    p ::= gpio.Pin LED-PIN --output
    p.set LED-VALUE
  
  /** sets the system+RTC time from NTP, and return how accurate
  the measurement was */
  ntp-accuracy ::= time-setup
  mqtt-setup
  mqtt-pub "Connected to mqtt"
  rtc-setup
  calulate-drift ntp-accuracy

/** Sets the system time using NTP. Returns the accuracy of the measurement */
time-setup -> Duration:
  coundown := 4
  while true:
    result := ntp.synchronize --server=NTP-SERVER
    if result:
      if result.accuracy < NTP-ERROR-MAX-SETUP:
        set_real_time_clock (Time.now + result.adjustment) // immediate time fix, not gradual
        print "\nNTP sync done, accuracy=$result.accuracy"
        return result.accuracy
      else:
        print "The accuracy of ntp is bad : $result.accuracy"
        if coundown>0:
          coundown--
        else:
          print "Increasing the error tolerance my 1ms"
          NTP-ERROR-MAX-SETUP += (Duration --ms=1)
    else:
      print "NTP synchronization failed"
    sleep --ms=5000

/** Connects to mqtt, for TLS you have to also setup a certificate */
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

/** helper function, sends the message to mqtt, handling possible errors */
mqtt-pub payload/string:
  print payload
  if client==null:
    print "Cannot send to mqtt, not connected."
    return
  err := catch:
    client.publish TOPIC payload --retain
  if err:
    print "Cannot publish : err = $err"
    mqtt-setup

/** Sets the system time from NTP and writes to the RTC */
rtc-setup:
  try:
    rtc.set (Duration --us=0) // we set the system time
  finally: | is-exception _ |
    if is-exception:
      mqtt-pub "ERROR writing to the RTC"
  try:
    adj := rtc.get
    print "The rtc has diff $adj from system time"
    // TODO the adj can be used to finetune the final accuracy
  finally: | is-exception _ |
    if is-exception:
      mqtt-pub "ERROR reading the RTC"
  

/** Endless loop, as time passes the difference between NTP and RTC grows */
calulate-drift setup-accuracy:
  start-time := Time.now
  mqtt-pub """
  \nWARNING: the first few measurements are worthless, but we
  print them anyway, to show that the program is working
  """
  sleep --ms=10_000
  aging-offset := null
  try:
    aging-offset = rtc.get-aging-offset
  finally: | is-exception _ |
    if is-exception:
      mqtt-pub "Error communicating with Ds3231. Cannot get rtc aging offset"
  if aging-offset==null:
    throw "Programming error"
  while true:
    result := ntp.synchronize --server=NTP-SERVER
    if result:
      if result.accuracy < NTP-ERROR-MAX:
        rtcadj := null
        try:
          rtcadj = rtc.get
        finally: | is-exception _ |
          if is-exception:
            mqtt-pub "Cannot get rtc aging offset"
        if rtcadj==null:
          throw "Programming error"
        diff ::= rtcadj - result.adjustment
        time-passed ::= start-time.to Time.now
        ppm ::= 1.0*1e6*diff.in-us/time-passed.in-us
        ppm-error ::= 1.0*1e6*(result.accuracy.in-us+setup-accuracy.in-us)/time-passed.in-us
        //print "$diff.in-us $time-passed.in-us $result.accuracy.in-us $time-passed.in-us"
        offs:= (ppm*10+0.5).to-int
        now ::= Time.now + result.adjustment
        loctime ::= now.local.stringify[..19]
        runtime ::= start-time.to now
        runtime-h-m ::= "\"$(runtime.in-h)h$(runtime.in-m%60)m\""
        next-measuremet ::= (now+CHECK-PERIOD).local.stringify[..19]
        msg := """{
  "TimeNow":"$loctime",
  "Runtime":$runtime-h-m,
  "Next Measurement":"$next-measuremet",
  "DS3231 SetupTime accuracy":"$(setup-accuracy.in-ms) ms",
  "NTP accuracy":"$(result.accuracy.in-ms) ms",
  "Time Keeping Accuracy":"$(%0.1f ppm) ppm",
  "Accuracy Uncertainty":"+/- $(%0.1f ppm-error) ppm",
  "IP-address":"$net.open.address",
  "Stored Aging Offset":$aging-offset
}"""
        mqtt-pub msg

        if ( (1.5*ppm-error) < ppm.abs) and (ppm.abs>0.1) and (ppm-error<0.5):
          write-offset := offs+aging-offset
          try:
            rtc.set-aging-offset write-offset
          finally: | is-exception _ |
            if is-exception:
              mqtt-pub "Cannot set aging offset"
          deep-sleep
            Duration --s=10 // restart the module
        sleep CHECK-PERIOD
      else:
        print "Bad NTP accuracy : $result.accuracy"
        // we want a result, so we retry soon
        sleep
          Duration --s=10
    else:
      print "NTP synchronization failed"
      sleep (Duration --s=10)
