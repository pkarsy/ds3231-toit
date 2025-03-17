import .ds3231
import esp32

main:
  /* gnd := gpio.Pin 32 --output --value=0
  vcc := gpio.Pin 33 --output --value=1
  bus := i2c.Bus --sda=(gpio.Pin 25) --scl=(gpio.Pin 26)
  device := bus.device ds3231.DEFAULT-I2C
  ds := ds3231 device */
  ds := Ds3231 --sda=25 --scl=26 --vcc=33 --gnd=32
  2.repeat:
    //ds.set
    print " tm=$(ds.get --fast)"
    print "sys=$Time.now"
    print ""
    print "stm=$ds.get"
    print "sys=$Time.now"
    print "################"
    sleep --ms=5_500
  



  run-time ::= Duration --us=esp32.total-run-time
  sleep-time ::= Duration --us=esp32.total-deep-sleep-time
  print "Awake for $(run-time - sleep-time) so far"
  print "Slept for $sleep-time so far"
  esp32.deep-sleep (Duration --s=10)
