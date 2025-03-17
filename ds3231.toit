import gpio
import i2c
import serial

/**
Toit Driver for the DS3231 Real Time Clock
C Panagiotis Karagiannis
MIT Licence

The driver can write the system time to the DS3231 chip
and can create a Time object by reading the DS3231
but it does not modify the system time, to avoid dependency on esp32 module
See the example on how to set the ESP32 time
*/

class Ds3231:
  static DEFAULT-I2C ::= 0x68 // This is different if we solder A1 A2 A3 pads
  static REG-START_ ::= 0x00  // The first register is at location 0x00
  static REG-NUM_ ::= 7       // and we read 7 consequitive reagisters
  registers_/serial.Registers

  constructor --device/serial.Device:
    registers_=device.registers
  
  constructor --sda/int --scl/int --vcc/int=-1 --gnd/int=-1 --addr/int=-1:
    bus := i2c.Bus --sda=(gpio.Pin sda) --scl=(gpio.Pin scl)
    if addr==-1:
      addr = Ds3231.DEFAULT-I2C
    device := bus.device addr
    registers_=device.registers
    if vcc >= 0:
      gpio.Pin vcc --output --value=1
    if gnd >= 0:
      gpio.Pin gnd --output --value=0

  get --fast=false -> Time:
    if not fast:
      //print "get slow"
      v := registers_.read-u8 REG-START_
      while true:
        sleep --ms = 10
        v1 := registers_.read-u8 REG-START_
        if v!=v1:
          break
    //else:
    //  print "get fast"
    buf := registers_.read-bytes REG-START_ REG-NUM_
    t := []
    buf.do:
      t.add (bcd2int_ it)
    utc := Time.utc --s=t[0] --m=t[1] --h=t[2] --day=t[4] --month=t[5] --year=2000+t[6]
    return utc
  
  set --fast=false --force=false:
    if Time.now.utc.year<2025 and force==false:
      print "The System time is incorrect. Use --force to write the time"
      return
    if fast==false:
      s := Time.now.utc.s
      while true:
        sleep --ms=10
        s1 := Time.now.utc.s
        if s1!=s:
          break
    u := Time.now.utc
    t := [u.s, u.m, u.h, u.weekday, u.day, u.month, (u.year - 2000)]
    buf := ByteArray REG-NUM_
    REG-NUM_.repeat:
      buf[it]=int2bcd_ t[it]
    registers_.write-bytes REG-START_ buf
  
  static int2bcd_ x/int -> int:
    return (x/10)*16+(x%10)
  
  static bcd2int_ x/int -> int:
    return (x/16)*10+(x%16)