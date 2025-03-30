# Ds3231
toit driver for the DS3231 real time clock.

## Warning
Working with time, especally if there are constrains on the accuracy, is a hard job. At the moment the library has limited testing and bugs are expected. Any help on inmpoving the driver is welcome.

## Installing
> jag pkg install github.com/pkarsy/toit-ds3231

## Connection
We need 4 pins:

> SCL SDA VCC GND

The popular blue DS3231 boards (and I think all boards, check the documentation) do not have level conversion circuitry. So the VCC pin should be connected to 3.3V. The current the breakout is consuming is minimal, and we can even use GPIO pins for the VCC and GND. See the examples.

## RTC Coin Cell
Note: We speak about the pupular blue breakout DS3231 board, with the primitive diode charging circuit.

Use a good CR2032 coin cell. Some internet sources mention LIR2032 (rechargable) but with 3.3V the rechargable cell cannot be charged at all, making the module unusable. The CR2032 is safe with 3.3V for the same reason the LIR2032 canot be charged (No reverse current)

## Accuracy
We can expect Time to be set and get with a less than 1-2ms error, but this in not the whole story. The DS3231 RTC clock can have up to 2ppm drift (0 - 40C) 

```
1 day : 0.17 sec
1 week : 1.2 sec
1 month : 5 sec
1 year : 1 min
```

The above values are more or less the worst cases, unless you expose the module to extreme temperatures. (See the Aging Correction below)

If the project can have internet access (even occasionally, for example a mobile phone as access point) the time could be fixed using NTP. See the "ntp-plus-rtc.toit" exanple.

The crystal of the ESP32 board normally has much worse performance than the TCXO crystal of the Ds3231, so it makes sense (when not using NTP) to update the system (ESP32) time every hour using the DS3231 time. See the example "nowifi.toit" for this.

All the above are only useful if you know the wanted accuracy. Some hints:

- For a project having NTP(internet) time and we want the RTC as a backup, the DS3231 is already extremly accurate.
- For projects expecting to be mostly without wifi, the aging correction can be useful, but again 1min error per year can be insignificant for many applications (irrigation timer comes to mind). Usually the calculation of the aging setting is hard to measure correctly and seems (according to internet sources) to be temparature dependend (I am not sure about this).
- For projects really isolated (from the internet) and still requiring high time precision, a GNSS module can be a solution (you have to solve other problems of course). For Toit-lang there are more than one GNSS drivers, but I have not tested them. I have created such a [driver for tasmota](https://github.com/pkarsy/TasmotaBerryTime/tree/main/ds3231) if you are interested.

## Developer Hints
- library documentation at [ds3231 toit registry](https://pkg.toit.io/github.com/pkarsy/toit-ds3231@0.8.2/docs/)
- Inspect the examples to see how they work in practice.
- The library does not raise exceptions, even on hardware errors (bad cabling for example). Instead the member functions either return directly the error (time set) or return null and the error variable is set with the error (time get).

### Constructor
We can create the driver instance with 2 ways.
- If we need the i2c bus for multiple peripherals, we must create the i2c bus object first, and then we pass it to the constructor.
- If the DS3231 is the only i2c in the bus (most common case) we can simply pass the pin numbers to the constructor.

### Setting and getting the time
This library, just like the esp-idf library and the ntp library, uses the time-adjustment instead of absolute time. This is a clever way to set the time correctly, even if there is a time gap between time-get and time-set

### SQW pin
The library does not use/need this pin by itself, but you may find it usefull for other purposes, as interrupt source etc. The following functions can control the SQW output.

```
enable-sqw-1hz
enable-sqw-1kilohz
enable-sqw-4kilohz
enable-sqw-8kilohz
disable-sqw
enable-battery-backed-sqw
disable-battery-backed-sqw
```

DS3232 will retain the register settings as long as the module is active or even battery backed.

### Temperature
> get-temperature

returns the temperature in °C.

### Clock drift
> get-drift

shows the expected time drift (assuming 2ppm error) since the last time the clock was set. The real drift is usually smaller. You can set the ppm error.

### ALARM 1/2
Not implemented at the moment.

### Aging correction

> set-aging-offset

Can get a value from -128 up to 127 to make the clock more accurate (much less than 2ppm). See
[this project](https://github.com/gbhug5a/DS3231-Aging-GPS), on how to measure this offset, but most of the time you dont need it.


### Chip operations not implemented by the driver
if you want to make register manipulations you can write for example (asuming the instance is called "rtc")

> rtc.set-value-with-mask --register=0x0e --value=0b0_1_000000 --mask=0x0_1_000000

sets only the bit-6 of the register 0x0E and enables battery backed SQW (Already implemented by the library by the way). All other bits are unchanged (dictated by mask).

> rtc.set-bits-with-mask --register=0x0E --bits=0b0_0_000000 --mask=0x0_1_000000

does the oposite.

If this is not enough, there is the rtc.registers object for raw manipulation, which is generally ever more error prone than the set-bits-with-mask function.

### VCC GND and battey powered projects
On battery, the 4mA the DS3231 is using, is a huge consumption. For this specific purpose the VCC and GND can be GPIO pins, and the DS3231 module is powered OFF when in deep-sleep. Assuming a good CR2032 coin cell, the time keeping function will stil work.
