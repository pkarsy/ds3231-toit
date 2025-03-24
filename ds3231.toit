

/**
Toit Driver for the DS3231 Real Time Clock
C Panagiotis Karagiannis
MIT Licence
URL todo
*/

import gpio
import i2c
import serial

class Result:
  adjustment/Duration? ::= ?
  error/string? ::= ?
  constructor .adjustment .error:
  stringify:
    return "{\"Adjustment-ms\":$adjustment.in-ms.to-int,\"Error\":$error}"


class Ds3231:
  static DEFAULT-I2C ::= 0x68 // This is different if we solder A1 A2 A3 pads
  static REG-START_ ::= 0x00  // The first register is at location 0x00
  static REG-NUM_ ::= 7       // and we read 7 consequitive reagisters
  registers_/serial.Registers ::= ?
  // We forward the time a few msec to compensate for the toit virtual
  // machine and i2c delays
  compensation_/Duration := Duration --ms=8

  constructor --device/serial.Device --compensation/Duration?=null:
    registers_=device.registers
    if compensation: compensation_ = compensation
  
  constructor --sda/int --scl/int --vcc/int=-1 --gnd/int=-1 --addr/int=-1 --compensation/Duration?=null:
    if compensation: compensation_ = compensation
    bus := i2c.Bus
      --sda = gpio.Pin sda
      --scl = gpio.Pin scl
    if addr==-1:
      addr = Ds3231.DEFAULT-I2C
    device := bus.device addr
    registers_=device.registers
    if vcc >= 0:
      gpio.Pin vcc --output --value=1
    if gnd >= 0:
      gpio.Pin gnd --output --value=0
  
  get --accurate=true --allow-wrong-time=false -> Result:
    rtctime/Time? := null
    exception := catch:
      if accurate:
        v := registers_.read-u8 REG-START_
        while true:
          yield
          v1 := registers_.read-u8 REG-START_
          if v!=v1:
            break
      rtctime = this.get_
    if exception or rtctime==null:
      return Result null exception
    else if  rtctime.utc.year<2025:
      return Result null "DS3231_TIME_IS_INVALID"
    else:
      return Result (Time.now.to rtctime) null

  set time/Time --accurate=true --allow-wrong-time=false -> string?:
    if allow-wrong-time==false and time.utc.year<2025:
      return "SYSTEM_TIME_IS_INVALID"
    if accurate: // waits until the second changes
      ms/Duration := Duration --ms = (time.utc.ns/1e6).to-int
      target-delay/Duration ::= ?
      if (ms + compensation_)  >= (Duration --ms=995) :
        target-delay = Duration --ms=2000
      else:
        target-delay = Duration --ms=1000
      delay/Duration ::= target-delay - ms - compensation_
      time = time + target-delay
      sleep delay
    exception := catch: this.set_ time
    if exception: return exception //failed to set the RTC, we return a description
    return null // no error

  get_ -> Time:
    // read-bytes can throw an exception
    buf := registers_.read-bytes REG-START_ REG-NUM_
    t := []
    buf.do:
      t.add (bcd2int_ it)
    utc := Time.utc --s=t[0] --m=t[1] --h=t[2] --day=t[4] --month=t[5] --year=2000+t[6]
    return utc
  
  set_ time/Time -> none:
    u := time.utc
    // must be 7 fields, the same as the Ds3231 registers
    t := [u.s, u.m, u.h, u.weekday, u.day, u.month, (u.year - 2000)]
    if t.size != REG-NUM_: throw "INCORRECT ELEMENTS NUMBER"
    buf := ByteArray REG-NUM_
    REG-NUM_.repeat:
      buf[it]=int2bcd_ t[it]
    // write-bytes can throw an exception
    registers_.write-bytes REG-START_ buf
  
  set-compensation comp/Duration:
    compensation_ = comp
  
  get-compensation -> Duration:
    return compensation_
  
  static int2bcd_ x/int -> int:
    return (x/10)*16+(x%10)
  
  static bcd2int_ x/int -> int:
    return (x/16)*10+(x%16)