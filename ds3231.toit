/**
Toit Driver for the DS3231 Real Time Clock
C Panagiotis Karagiannis
MIT Licence
URL todo
*/

import gpio
import i2c
import serial

class Ds3231:
  static DEFAULT-I2C ::= 0x68 // This is different if we solder A1 A2 A3 pads
  static REG-START_ ::= 0x00  // The first register is at location 0x00
  static REG-NUM_ ::= 7       // and we read 7 consequitive reagisters
  registers/serial.Registers ::= ?
  error/string? := null
  last-set-time_/Time? := null 

  constructor --device/serial.Device :
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
    registers = device.registers
    if vcc >= 0:
      gpio.Pin vcc --output --value=1
    if gnd >= 0:
      gpio.Pin gnd --output --value=0
  
  get --wait-sec-change=true
      --allow-wrong-time=false 
      -> Duration? :
    tstart:=Time.now
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
      error="GET_PROGRAMMING_ERROR"
      return null
    adj:=Time.now.to rtctime
    if rtctime.utc.year<2025:
      error="DS3231_TIME_IS_INVALID"
      return null
    else:
      return adj

  set --adjustment/Duration
      --wait-sec-change=true
      --allow-wrong-time=false
      -> string? : // error as string or null
    adjustment += Duration --us=1750 // we compensate for the i2c and MCU delays
    if allow-wrong-time==false and (Time.now + adjustment).utc.year<2025:
      return "YEAR_LESS_THAN_2025"
    t := Time.now + adjustment
    if wait-sec-change: // wait until the second changes for better accuracy
      s := t.utc.s
      while true:
        yield
        t = Time.now+adjustment
        s1 := t.utc.s
        if s!=s1: break
    exception := catch: this.set_ Time.now+adjustment
    if exception: return exception //failed to set the RTC, we return a description
    last-set-time_ = t
    return null // no error

  get_ -> Time :
    // read-bytes can throw an exception
    buf := registers.read-bytes REG-START_ REG-NUM_
    t := []
    buf.do:
      t.add (bcd2int_ it)
    utc := Time.utc --s=t[0] --m=t[1] --h=t[2] --day=t[4] --month=t[5] --year=2000+t[6]
    return utc
  
  set_ tm/Time -> none :
    u := tm.utc
    // must be 7 fields, the same as the Ds3231 time keeping registers
    t := [u.s, u.m, u.h, u.weekday, u.day, u.month, (u.year - 2000)]
    // We can get this error only by messing with the "t" fields, so not really useful
    // if t.size != REG-NUM_: throw "INCORRECT_ELEMENTS_NUMBER"
    buf := ByteArray REG-NUM_
    REG-NUM_.repeat:
      buf[it]=int2bcd_ t[it]
    // write-bytes can throw an exception
    registers.write-u8 REG-START_ 0 // to reset the countdown timer
    registers.write-bytes REG-START_ buf
  
  // use only if you already have a value for example
  // The new value will work after the next temp conversion
  // values are -128 up to 127
  set-aging-offset val/int -> string? :
    aging-register ::= 0x10 // Ds3231 datasheet
    if (val<-128) or (val>127):
      return "WRONG_AGING_OFFSET"
    err:= catch:
      registers.write-i8 0x10 val
    return err

  set-sqw_ value -> string? :
    return set-value-with-mask
      --register=0x0e
      --mask=0b000_111_00
      --value=value
  
  // mask is a value with all bits to be changed (and only them) set to 1
  // value is a byte containing the values 0/1 we want to apply (only the 1s in the mask)
  // returns null if no error otherwise returns the error as a string
  set-value-with-mask --register/int --mask/int --value/int -> string?:
    if not (0<=register<=0x12 and 0<=mask<=255 and 0<=value<=255):
      return "PARAMETERS_OUT_OF_BOUNDS"
    new-value := value
    old-value/int? := null
    err := catch:
      old-value = registers.read-u8 register
    if err:
      return err
    if old-value==null:
      return "SET-VALUE-PROGRAMMING-ERROR"
    value-to-apply := (old-value & ~mask) | (new-value & mask)
    err = catch:
      registers.write-u8 register value-to-apply
    return err

  enable-sqw-1hz -> string? :
    return set-sqw_ 0b000_000_00 // RS2->0 RS1->0 INTCN->0
  
  enable-sqw-1kilohz -> string?:
    return set-sqw_ 0b000_010_00
  
  enable-sqw-4kilohz -> string? :
    return set-sqw_ 0b000_100_00
  
  enable-sqw-8kilohz -> string? :
    return set-sqw_ 0b000_110_00
  
  disable-sqw -> string? :
    return set-sqw_ 0b000_111_00
  
  enable-battery-backed-sqw -> string? :
    return set-value-with-mask --register=0x0e --value=0b0_1_000000 --mask=0x0_1_000000
  
  disable-battery-backed-sqw -> string? :
    return set-value-with-mask --register=0x0e --value=0b0_0_000000 --mask=0x0_1_000000
  
  temperature -> int? :
    temperature-register := 0x11 // Ds3231 datasheet
    error = catch:
      // the value is stored as a 8-bit 2-complement number, and read-i8 reads exactly this
      t := registers.read-i8 temperature-register
      return t
    return null

  drift --ppm/float=2.0 -> Duration?:
    t/Time := Time.now
    if last-set-time_==null:
      error = "THE_TIME_IS_NEVER_WRITTEN_TO_DS3231"
      return null
    return (last-set-time_.to t)*ppm/1e6
    
  // Date/Time is stored to the registers in BCD
  static int2bcd_ x/int -> int:
    return (x/10)*16+(x%10)
  
  static bcd2int_ x/int -> int:
    return (x/16)*10+(x%16)