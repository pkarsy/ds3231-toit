import gpio
import i2c
import serial

/**
Toit driver for the DS3231 Real Time Clock.
*/

/**
A string with an error message.
All library functions that do not return a value, return null or an Error object.

class Error:
  error/string ::= ?

  constructor .error:

  stringify:
    return error

  operator == other:
    if other is string:
      return error == other
    else if other is Error:
      return error == other.error
    else:
      return false
*/

/**
The result of getting the time from the DS3231.

Contains 2 fields :
- $adjustment, $Duration or null.
- $error, string or null.

class Result:
  adjustment/Duration?
  error/string?

  constructor .adjustment .error:

  stringify:
    return "{\"Time\":$adjustment,\" Error\":$error}"
*/

/**
Driver for the DS3231 Real Time Clock.
*/
class Ds3231:
  /** Deprecated. Use $I2C-ADDRESS instead. */
  static DEFAULT-I2C ::= I2C-ADDRESS

  /**
  The default i2c adress of the DS3231 is 0x68.
  You can change the i2c address with A0 A1 A2 pins/pads.
  */
  static I2C-ADDRESS ::= 0x68

  static REG-START_ ::= 0x00  // The first time (seconds) register is at location 0x00.
  static REG-NUM_ ::= 7       // and we read 7 consequitive reagisters, until years (2 digits).

  static REG-AGING_ ::= 0x10 // The aging register.
  static REG-TEMPERATURE_ ::= 0x11 // the one with the whole number. The next contains decimals.

  /**
  For direct register read/write.
  A little more friendly is the "set-value-with-mask" function.
  */
  registers_/serial.Registers? := null
  last-set-time_/Time? := null

  /** The I2C bus. Null, if not allocated by this class. */
  bus_/i2c.Bus? := null
  /** The sda-pin. Null, if not allocated by this class. */
  sda_/gpio.Pin? := null
  /** The scl-pin. Null, if not allocated by this class. */
  scl_/gpio.Pin? := null
  /** The vcc pin, if specified. */
  vcc_/gpio.Pin? := null
  /** The gnd pin, if specified. */
  gnd_/gpio.Pin? := null

  /**
  Creates a Ds3231 instance, given a serial.Device object.

  Deprecated. Use $(constructor device) instead.
  */
  constructor --device/serial.Device :
    registers_ = device.registers

  /**
  Creates a Ds3231 instance, given a serial.Device object
  */
  constructor device/serial.Device :
    registers_ = device.registers

  /**
  Variant of $(constructor device).

  Cnonvenience function to build an i2s bus/device during construction.

  If given, $vcc/$gnd are initialized as output pins with the corresponding levels.
    This simplifies the Ds3231 cabling, and allows to save power when the ESP32 goes
    to sleep.
  */
  constructor
      --sda/int
      --scl/int
      --vcc/int? = null
      --gnd/int? = null
      --addr/int = I2C-ADDRESS:
    //registers := null
    try:
      sda_ = gpio.Pin sda
      scl_ = gpio.Pin scl
      bus_ = i2c.Bus --sda=sda_ --scl=scl_
      device := bus_.device addr
      registers_ = device.registers
      if vcc and vcc >= 0:
        vcc_ = gpio.Pin vcc --output --value=1
      if gnd and gnd >= 0:
        gnd_ = gpio.Pin gnd --output --value=0
    finally: | is-exception _ |
      if is-exception:
        if bus_: bus_.close
        if sda_: sda_.close
        if scl_: scl_.close
        if vcc_: vcc_.close
        if gnd_: gnd_.close
    // Work-around for https://github.com/toitlang/toit/issues/2758.
    // registers_ = null //registers

  /** Closes this driver. */
  close -> none:
    if bus_:
      bus_.close
      bus_ = null
    if sda_:
      sda_.close
      sda_ = null
    if scl_:
      scl_.close
      scl_ = null
    if vcc_:
      vcc_.close
      vcc_ = null
    if gnd_:
      gnd_.close
      gnd_ = null

  /**
  Reads the time from the Ds3231 chip.

  If $wait-sec-change is false the function returns immediately but can have a time
    error of up to 1 second.
  If $wait-sec-change is true (the default), this function can block up to 1 sec but
    the adjustment is accurate to about 1 ms.

  If $allow-wrong-time is true, checks that the time is at least 2025.
  */
  get -> Duration
      --wait-sec-change/bool = true
      --allow-wrong-time/bool = false:
    tstart := Time.now
    rtctime/Time? := null
    //error := catch:
    if wait-sec-change:
      v := registers_.read-u8 REG-START_
      while true:
        yield
        v1 := registers_.read-u8 REG-START_
        if v != v1:
          break
    rtctime = this.get_ // The time is read just when the second register goes to the next second.
    //if error:
    //  return Result null error
    //if rtctime == null:
    //  error = "GET_PROGRAMMING_ERROR"
    //  return Result null error
    adjustment := Time.now.to rtctime
    if not allow-wrong-time and rtctime.utc.year < 2025:
      //return Result null "DS3231_TIME_IS_INVALID"
      throw "DS3231_TIME_IS_INVALID"
    //else:
    //  return Result adjustment null
    return adjustment

  /**
  Sets the RTC time to Time.now+adjustment.

  See $get for the meaning of $wait-sec-change and $allow-wrong-time.

  Retuns null on success, and the error otherwise.*/
  set adjustment/Duration
      --wait-sec-change/bool=true
      --allow-wrong-time/bool=false -> none :
    adjustment += Duration --us=1750 // We compensate for the i2c and MCU delays.
    if not allow-wrong-time and (Time.now + adjustment).utc.year < 2025:
      //error := "YEAR_LESS_THAN_2025"
      //return Error error
      throw "YEAR_LESS_THAN_2025"
    t := Time.now + adjustment
    if wait-sec-change: // Wait until the second changes for better accuracy.
      s := t.utc.s
      while true:
        yield // allows other code to run
        t = Time.now + adjustment
        s1 := t.utc.s
        if s != s1: break
    set_ (Time.now + adjustment)
    //if error:
    //  return Error error //Failed to set the RTC, we return a description.
    // No error happened.
    last-set-time_ = t
    //return null

  get_ -> Time:
    // read-bytes can throw an exception.
    buffer := registers_.read-bytes REG-START_ REG-NUM_
    t := []
    buffer.do:
      t.add (bcd2int_ it)
    utc := Time.utc --s=t[0] --m=t[1] --h=t[2] --day=t[4] --month=t[5] --year=(2000 + t[6])
    return utc

  set_ tm/Time -> none :
    u := tm.utc
    // Must be 7 fields, the same as the Ds3231 time keeping registers.
    t := [u.s, u.m, u.h, u.weekday, u.day, u.month, (u.year - 2000)]
    // We can get this error only by messing with the "t" fields, so not really useful.
    // if t.size != REG-NUM_: throw "INCORRECT_ELEMENTS_NUMBER"
    buffer := ByteArray REG-NUM_: int2bcd_ t[it]
    // write-bytes can throw an exception.
    registers_.write-u8 REG-START_ 0 // To reset the countdown timer.
    registers_.write-bytes REG-START_ buffer

  /**
  Sets the aging offset.

  The offset can me measured by following the instructions from
    https://github.com/gbhug5a/DS3231-Aging-GPS
  The new value will work after the next temp conversion.
  The $offset must satisfy -128 <= $offset < 127.
  */
  set-aging-offset offset/int -> none:
    if not -128 <= offset <= 127: throw "INVALID_ARGUMENT"
    //error/string? := catch:
    registers_.write-i8 REG-AGING_ offset
    //return Error error

  set-sqw_ value -> none:
    //return 
    set-value-with-mask
        --register=0x0e
        --mask=0b000_111_00
        --value=value

  /**
  Sets some bits of the given $register.

  Uses the given $mask to select the bits that should be changed.
  No bits outside the $mask are changed.

  The given $value is applied unshifted (but masked).
  */
  set-value-with-mask --register/int --mask/int --value/int -> none:
    if not (0 <= register <= 0x12 and 0 <= mask <= 255 and 0 <= value <= 255):
      //return Error "PARAMETERS_OUT_OF_BOUNDS"
      throw "PARAMETERS_OUT_OF_BOUNDS"
    new-value := value
    //old-value/int? := null
    //error/string? := catch:
    old-value/int := registers_.read-u8 register
    //if error:
    //  return Error error
    //if not old-value:
    //  error = "SET-VALUE-PROGRAMMING-ERROR"
    //  return Error error
    value-to-apply := (old-value & ~mask) | (new-value & mask)
    //error = catch:
    registers_.write-u8 register value-to-apply
    //if error:
    //  return Error error
    //else:
    //  return null

  /** Deprecated. Use $enable-sqw-output instead. */
  enable-sqw-1hz -> none :
    set-sqw_ 0b000_000_00 // RS2->0 RS1->0 INTCN->0

  /** Deprecated. Use $enable-sqw-output instead. */
  enable-sqw-1kilohz -> none:
    set-sqw_ 0b000_010_00

  /** Deprecated. Use $enable-sqw-output instead. */
  enable-sqw-4kilohz -> none :
    set-sqw_ 0b000_100_00

  /** Deprecated. Use $enable-sqw-output instead. */
  enable-sqw-8kilohz -> none :
    set-sqw_ 0b000_110_00

  /**
  Enables the given $frequency on the sqw pin.

  The output is push-pull and doesn't need any pull-up or pull-down.

  The $frequency must be one of 1, 1000, 4000, or 8000.
  */
  enable-sqw-output --frequency/int -> none:
    if frequency == 1: set-sqw_ 0b000_000_00 // RS2->0 RS1->0 INTCN->0.
    else if frequency == 1000: set-sqw_ 0b000_010_00
    else if frequency == 4000: set-sqw_ 0b000_100_00
    else if frequency == 8000: set-sqw_ 0b000_110_00
    else: throw "INVALID_ARGUMENT"


  /** Disables the output on the sqw pin. */
  disable-sqw -> none :
    set-sqw_ 0b000_111_00

  /**
  Enables the battery-backed sqw.

  This is generally not a good idea. Be especially careful not to
    connect any pull-up or pull-down (even software enabled). It's not necesary,
    and will consume precious energy from the coin-cell.
  */
  enable-battery-backed-sqw -> none :
    set-value-with-mask --register=0x0e --value=0b0_1_000000 --mask=0x0_1_000000

  /**
  Disables the battery-backed sqw.
  This is the default DS3231 setting.
  */
  disable-battery-backed-sqw -> none :
    set-value-with-mask --register=0x0e --value=0b0_0_000000 --mask=0x0_1_000000

  /** Returns the temperature in celsius. The chip has a second register
  with 0.25 degrees granularity but it is ignored.
  */
  get-temperature -> int :
    //error := catch:
    // The value is stored as a 8-bit 2-complement number.
    //  return 
    return registers_.read-i8 REG-TEMPERATURE_
    //return null

  /**
  Returns the expected drift.

  The drift is calculated by assuming a 2ppm error since the last time the clock is set.
  if the time was never stored, in the lifetime of the object, it returns null. The
  drift is usually smaller, and in some cases (high temperature changes) can be greater.
  */
  expected-drift --ppm/num=2 -> Duration?:
    ppm = ppm * 1.0 // to be sure is float
    t/Time := Time.now
    if not last-set-time_: return null
    return (last-set-time_.to t) * ppm / 1e6

  /** seconds minutes hours etc. are stored in the DS3231 registers as BCD. */
  static int2bcd_ x/int -> int:
    return (x / 10) * 16 + (x % 10)

  static bcd2int_ x/int -> int:
    return (x / 16) * 10 + (x % 16)
