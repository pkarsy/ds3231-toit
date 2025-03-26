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
  // We do not hide the registers (using registers_)
  // as there is a myriad of settings this driver does not cover
  registers/serial.Registers ::= ?
  // We forward the time a few msec to compensate for the toit virtual
  // machine and i2c delays
  compensation_ := Duration --ms=8
  error/string? := null

  constructor
      --device/serial.Device :
    registers=device.registers

  constructor
      --sda/int
      --scl/int
      --vcc/int=-1
      --gnd/int=-1
      --addr/int=-1 :
    bus := i2c.Bus
      --sda = gpio.Pin sda
      --scl = gpio.Pin scl
    if addr==-1:
      addr = Ds3231.DEFAULT-I2C
    device := bus.device addr
    registers=device.registers
    if vcc >= 0:
      gpio.Pin vcc --output --value=1
    if gnd >= 0:
      gpio.Pin gnd --output --value=0
  
  get --wait-sec-change=true
      --allow-wrong-time=false 
      -> Duration? :
    rtctime/Time? := null
    exception := catch:
      if wait-sec-change:
        v := registers.read-u8 REG-START_
        while true:
          yield
          v1 := registers.read-u8 REG-START_
          if v!=v1:
            break
      rtctime = this.get_
    if exception:
      error = exception
      return null
    if rtctime==null:
      error="NO_TIME_PROGRAMMING_ERROR"
      return null
    if rtctime.utc.year<2025:
      error="DS3231_TIME_IS_INVALID"
      return null
    else:
      return
        Time.now.to rtctime

  set time/Time
      --wait-sec-change=true
      --allow-wrong-time=false
      -> string? :
    if allow-wrong-time==false and time.utc.year<2025:
      return "YEAR_LESS_THAN_2025"
    if wait-sec-change: // waits until the second changes
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

  get_ -> Time :
    // read-bytes can throw an exception
    buf := registers.read-bytes REG-START_ REG-NUM_
    t := []
    buf.do:
      t.add (bcd2int_ it)
    utc := Time.utc --s=t[0] --m=t[1] --h=t[2] --day=t[4] --month=t[5] --year=2000+t[6]
    return utc
  
  set_ time/Time -> none :
    u := time.utc
    // must be 7 fields, the same as the Ds3231 registers
    t := [u.s, u.m, u.h, u.weekday, u.day, u.month, (u.year - 2000)]
    // We can get this error only by messing with the fields
    if t.size != REG-NUM_: throw "INCORRECT ELEMENTS NUMBER"
    buf := ByteArray REG-NUM_
    REG-NUM_.repeat:
      buf[it]=int2bcd_ t[it]
    // write-bytes can throw an exception
    registers.write-bytes REG-START_ buf
  
  // use only if you already have a value for example
  // using TODO
  // The new value will work after the next temp conversion
  // values are -128 up to 127 (an 8 bit signed number)
  set-aging-offset val/int -> string? :
    aging-register ::= 0x10 // Ds3231 datasheet
    if (val<-128) or (val>127):
      return "WRONG_AGING_OFFSET"
    err:= catch:
      registers.write-i8 0x10 val
    return err

  enable-sqw_ bits -> string? :
    if bits<0 or bits>255:
      return "VALUE_OUT_OF_RANGE"
    // mask is a value with all bits to be changed (and only them) set to 1
    // newvalue is a value that contains the new state of those bits
    // the other bits are ignored.
    control-register := 0x0E // Ds3231 datasheet
    // DELETE debug 
    //registers.write-u8 control-register 0b11100
    mask ::= 0b000_111_00 // any 0 will be ignored when setting the bits
    value/int := -1
    err:= catch:
      value = registers.read-u8 control-register
    if err :
      return err
    if value==-1:
      return "PROGARMMING_BUG"
    //print value
    // we set 0/1 only to the bits where mask has 1
    new-value := setbits --value=value --mask=mask --bits=bits // (value & ~mask) | (bits & mask);
    //print "value=0b$(%08b value) new=0b$(%08b new-value)"
    registers.write-u8 control-register new-value
    return null
  
  setbits --value/int --mask/int --bits/int -> int:
    return (value & ~mask) | (bits & mask);

  // TThe library does not use the SQW pin but you may want it for other purposes
  enable-sqw-1hz -> string? :
    return enable-sqw_ 0b000_000_00 // RS2->0 RS1->0 INTCN->0 0b000_000_00 is the same
  
  enable-sqw-1kilohz -> string?:
    return enable-sqw_ 0b000_010_00
  
  enable-sqw-4kilohz -> string? :
    return enable-sqw_ 0b000_100_00
  
  enable-sqw-8kilohz -> string? :
    return enable-sqw_ 0b000_110_00
  
  disable-sqw -> string? :
    return enable-sqw_ 0b000_111_00

  // has nothing to do with RTC registers. It just tries to
  // compensate for the inaccuracies of the bus and MCU finite speed
  // the default is usually OK
  set-compensation comp/Duration:
    compensation_ = comp
  
  get-compensation -> Duration:
    return compensation_
  
  // Date/Time is stored to the registers in BCD
  static int2bcd_ x/int -> int:
    return (x/10)*16+(x%10)
  
  static bcd2int_ x/int -> int:
    return (x/16)*10+(x%16)