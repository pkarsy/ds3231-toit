/**
  Toit driver for the DS3231 Real Time Clock
*/

import gpio
import i2c
import serial

/**
A string with an error message.
All library functions that do not return a value, in fact return null or an Error object
*/
class Error:
  error/string ::= ?
  constructor .error:
  stringify:
    return error
  operator == other:
    return identical error other

/**
Contains 2 fiels :
- adjustment(Duration or null)
- error(string or null)
It is the result of the get function
*/
class Result:
  adjustment/Duration? ::= ?
  error/string? ::= ?
  constructor .adjustment .error:
  stringify:
    return "{\"Time\":$adjustment,\" Error\":$error}"

/**
  Toit driver for the DS3231 Real Time Clock
*/
class Ds3231:
  /**
    The default i2c adress of the DS3231 is 0x68. However you can change the i2c address with A0 A1 A2 pins/pads
  */
  static DEFAULT-I2C ::= 0x68
  static REG-START_ ::= 0x00  // The first register is at location 0x00
  static REG-NUM_ ::= 7       // and we read 7 consequitive reagisters
  /**
  For direct register read/write. A little more friendly is the "set-value-with-mask" function
  */
  registers/serial.Registers ::= ?
  last-set-time_/Time? := null 

  /**
    Creates a Ds3231 instance, given a serial.Device object
  */
  constructor --device/serial.Device :
    registers=device.registers

  /**
    A more convenient version of the constructor.
    We give the pin numbers, and the serial.Device is created by the constructor.
    We can also give vcc and gnd pin numbers, to power the module with theese gpio pins. This simplifies the Ds3231 cabling, and allows to save power when the ESP32 goes to sleep.
  */
  constructor
      --sda/int
      --scl/int
      --vcc/int? = null
      --gnd/int? = null
      --addr/int=DEFAULT-I2C :
    bus := i2c.Bus
      --sda = gpio.Pin sda
      --scl = gpio.Pin scl
    device := bus.device addr
    registers = device.registers
    if (vcc != null) and (vcc >= 0) :
      gpio.Pin vcc --output --value=1
    if (gnd != null) and (gnd >= 0):
      gpio.Pin gnd --output --value=0
  
  /**
    Reads the time from the Ds3231 chip.
    If wait-sec-change==false the function returns immediatelly but can have up to 1 sec time error.
    if wait-sec-change==true (the default) the function can block up to 1 sec but the adjustment is accurate to about 1 ms.
    if allow-wrong-time==false (the default) the time is checked if at least is 2025, otherwise returns error.
    Returns the time-adjustment, or null on error
  */
  get --wait-sec-change/bool = true
      --allow-wrong-time/bool = false 
      -> Result :
    tstart := Time.now
    rtctime/Time? := null
    error := catch:
      if wait-sec-change:
        v := registers.read-u8 REG-START_
        while true:
          yield
          v1 := registers.read-u8 REG-START_
          if v!=v1:
            break
      rtctime = this.get_
    if error:
      return (Result null error)
    if rtctime == null:
      error="GET_PROGRAMMING_ERROR"
      return (Result null error)
    adjustment := Time.now.to rtctime
    if rtctime.utc.year<2025:
      return (Result null "DS3231_TIME_IS_INVALID")
    else:
      error = null
      return (Result adjustment null)

  /**
    Sets the RTC time to Time.now+adjustment. The wait-sec-change and allow-wrong-time have the same meaning as the get function. On success returns null otherwise returns the error.
  */
  set --adjustment/Duration
      --wait-sec-change/bool=true
      --allow-wrong-time/bool=false
      -> Error? : // error as string or null
    adjustment += Duration --us=1750 // we compensate for the i2c and MCU delays
    if allow-wrong-time==false and (Time.now + adjustment).utc.year<2025:
      error := "YEAR_LESS_THAN_2025"
      return (Error error)
    t := Time.now + adjustment
    if wait-sec-change: // wait until the second changes for better accuracy
      s := t.utc.s
      while true:
        yield // allows other code to run
        t = Time.now + adjustment
        s1 := t.utc.s
        if s!=s1: break
    error/string? := catch: this.set_ Time.now + adjustment
    if error:
      return (Error error) //failed to set the RTC, we return a description
    // no error happened
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
  
  /**
    The offset can me measured by following the instructions from
    https://github.com/gbhug5a/DS3231-Aging-GPS
    The new value will work after the next temp conversion
    values are -128 up to 127
  */
  set-aging-offset offset/int -> Error? :
    aging-register ::= 0x10 // Ds3231 datasheet
    if (offset<-128) or (offset>127):
      return (Error "WRONG_AGING_OFFSET")
    error/string? := catch:
      registers.write-i8 0x10 offset
    return (Error error)

  set-sqw_ value -> Error? :
    return set-value-with-mask
      --register=0x0e
      --mask=0b000_111_00
      --value=value
  
  /**
    mask is a value with all bits to be changed (and only them) set to 1
    value is a byte containing the values 0/1 we want to apply (only the 1s in the mask)
    returns null if no error otherwise returns the error as a string
  */
  set-value-with-mask --register/int --mask/int --value/int -> Error?:
    if not (0<=register<=0x12 and 0<=mask<=255 and 0<=value<=255):
      return Error "PARAMETERS_OUT_OF_BOUNDS"
    new-value := value
    old-value/int? := null
    error/string? := catch:
      old-value = registers.read-u8 register
    if error:
      return (Error error)
    if old-value==null:
      error = "SET-VALUE-PROGRAMMING-ERROR"
      return Error error
    value-to-apply := (old-value & ~mask) | (new-value & mask)
    error = catch:
      registers.write-u8 register value-to-apply
    if error:
      return Error error
    else:
      return null

  /**
    1 Hz output on the SQW pin. The output is push-pull so no need for pull-up or pull-down.
  */
  enable-sqw-1hz -> Error? :
    return set-sqw_ 0b000_000_00 // RS2->0 RS1->0 INTCN->0
  
  enable-sqw-1kilohz -> Error?:
    return set-sqw_ 0b000_010_00
  
  enable-sqw-4kilohz -> Error? :
    return set-sqw_ 0b000_100_00
  
  enable-sqw-8kilohz -> Error? :
    return set-sqw_ 0b000_110_00
  
  disable-sqw -> Error? :
    return set-sqw_ 0b000_111_00
  
  /** Not a good idea generally. Be especially careful that do not connect (or software enable) pull-up or pull-down. Is not necesary, and will eat precious energy from the coin-cell */
  enable-battery-backed-sqw -> Error? :
    return set-value-with-mask --register=0x0e --value=0b0_1_000000 --mask=0x0_1_000000
  
  /** This is the default DS3231 setting */
  disable-battery-backed-sqw -> Error? :
    return set-value-with-mask --register=0x0e --value=0b0_0_000000 --mask=0x0_1_000000
  
  /** In celsious */
  get-temperature -> int? :
    temperature-register := 0x11 // Ds3231 datasheet
    error := catch:
      // the value is stored as a 8-bit 2-complement number, and read-i8 reads exactly this
      t := registers.read-i8 temperature-register
      return t
    return null

  /** The drift is calculated by assuming a 2ppm error since the last time the clock is set */
  expected-drift --ppm/num=2 -> Duration?:
    ppm = ppm * 1.0 // to be sure is float
    t/Time := Time.now
    if last-set-time_==null:
      return null
    return (last-set-time_.to t)*ppm/1e6
    
  /** Date/Time is stored to the DS3231 registers as BCD */
  static int2bcd_ x/int -> int:
    return (x/10)*16+(x%10)
  
  static bcd2int_ x/int -> int:
    return (x/16)*10+(x%16)
