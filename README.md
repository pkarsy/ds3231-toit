# Ds3231
[Toit](https://toitlang.org/) driver for the DS3231 real time clock.

## Warning
Working with time, especially if there are constraints on the accuracy, is a
hard job. At the moment the library has limited testing and bugs are expected.
Any help on inmpoving the driver is welcome.

## Installing + documentation
See [ds3231 at Toid package registry](https://pkg.toit.io/search?query=ds3231)

## Connection
You need 4 pins:

> SCL SDA VCC GND

The popular blue DS3231 boards (check the documentation for your board) do not
have level conversion circuitry. So the VCC pin should be connected to 3.3V.
The breakout consumes minimal current, and you can use GPIO pins for the VCC and
GND. See the examples.

## RTC Coin Cell
Note: This section applies to the popular blue DS3231 breakout board, with the
primitive diode charging circuit.

Use a good CR2032 coin cell. Some internet sources mention LIR2032 (rechargable)
but with 3.3V (see the above paragraph) the rechargable cell cannot be charged
at all, making the module unusable. The CR2032 is safe with 3.3V for the same
reason the LIR2032 canot be charged (No reverse current, as the diode has a voltage
 drop ~0.7 Volt). You can remove the diode as many sources mention, but it is
 not necessary if you power the module with 3.3V only.

## Accuracy
You can expect to get and set the time with a less than 1-2ms error.
However, the DS3231 RTC clock can have up to 2ppm drift (0 - 40C).

```
1 day : 0.17 sec
1 week : 1.2 sec
1 month : 5 sec
1 year : 1 min
```

The above values are more or less the worst cases, unless you expose the module
to extreme temperatures. (See the Aging Correction below)

If the project can have internet access (even occasionally, for example a mobile
phone as access point) the time could be fixed using NTP. See the
"ntp-plus-rtc.toit" exanple.

The crystal of the ESP32 board normally has much worse performance than
the TCXO crystal of the Ds3231, and it makes sense (when not using NTP) to
update the system (ESP32) time every hour using the DS3231 time. See
the example "nowifi.toit" for this.

All the above are only useful if you know the wanted accuracy. Some hints:

- For a project having NTP(internet) time and we want the RTC as a backup,
  the DS3231 is already extremely accurate.
- For projects expecting to be mostly without wifi, the aging correction can be
  useful, but a 1 minute error per year can still be insignificant 
  (irrigation timer comes to mind). Usually the calculation of the aging setting is
  hard to measure correctly and seems (according to internet sources) to be
  temperature dependend (I am not sure about this).
- For projects really isolated (from the internet) and still requiring high time
  precision, a GNSS module can be a solution (you have to solve other problems of
  course). For Toit there are more than one GNSS drivers, but I have not tested them.
  I have created such a
  [driver for tasmota](https://github.com/pkarsy/TasmotaBerryTime/tree/main/ds3231)
  if you are interested.

## Developer Hints
- library documentation at [ds3231 @ toit package registry](https://pkg.toit.io/search?query=ds3231)
- Inspect the examples to see how they work in practice.
- Almost all library calls can raise exceptions, for example when the cabling is bad.

### Constructor
You can create the driver instance in 2 ways.
- Create the i2c bus object first, and then pass it to the constructor.
- If the DS3231 is the only i2c device in the bus (most common case) you
  can simply pass the pin numbers to the constructor.

### Setting and getting the time
This library, just like the ntp library, uses time-adjustment instead of absolute
time. This is a clever way to set the time correctly, even if there is a time gap
between time-get (for instance from NTP) and time-set (to the DS3231)

### SQW pin
The library does not use/need this pin by itself, but you may find it usefull
for other purposes, as interrupt source etc. The following functions can
control the SQW output.

```
enable-sqw-output
disable-sqw
enable-battery-backed-sqw
disable-battery-backed-sqw
```

DS3232 will retain the register settings as long as the module is active or
is battery backed.

### Temperature
> get-temperature

returns the temperature in °C. Internally is updated every about 1 min (SN model).

### Clock drift
> expected-drift

shows the expected time drift (assuming 2ppm error) since the last time the clock
was set. The real drift is usually smaller. You can set the ppm error.

### ALARM 1/2
Not implemented at the moment.

### Aging correction

> set-aging-offset

Can get a value from -128 up to 127 to make the clock more accurate (much less than 2ppm).
- inside tools/ there is the **offset-calculator.toit app**. The hardware setup is minimal a
  ESP32x and a Ds3231 module(a lipo cell is a plus). It is very slow, but you can use
  multiple modules to setup more Ds3231 in parallel.
- [this project](https://github.com/gbhug5a/DS3231-Aging-GPS), is much faster but also
  has more work(and hardware) to implement.

### VCC GND and battey powered projects
On battery, the 4mA the DS3231 is using, is a huge consumption. For this specific
purpose the VCC and GND can be GPIO pins, and the DS3231 module is powered OFF when
in deep-sleep. Assuming a good CR2032 coin cell, the time keeping function will
still work and the registers will retain their values.
