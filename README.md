# Ds3231
toit driver for the DS3231 real time clock.

## Connection
We need 4 pins:

> VCC GND SCL SDA.

The popular blue DS3231 boards do not have level conversion circuitry and the VCC pin should be connected to 3.3V. The current the breakout is consuming is minimal, something like 4mA and for this reason we can even use GPIO pins for the VCC and GND. See the examples.

## Battery
Use a new CR2032 coin cell. Some old internet sources mention LIR2032 (rechargable) but with 3.3V the rechargable cell cannot be charged at all, making the module unusable.

## Accuracy
We can expect Time to be set and get with a less than 10ms error. 

However the RTC clock can have up to 2ppm drift (0 - 40C) 
```
1 day : 0.17 sec
1 week : 1.2 sec
1 month : 5 sec
1 year : 1 min
```

Theese values are more or less the worst cases, Unless you expose the module to extreme temperatures. You can do even better by setting the aging register with a suitable offset.
https:// TODO

If the project can have internet access (even accasionally, for example a mobile phone as access point) the time could be fixed using NTP. There is the rtc+ntp.toid doing this in the examples folder.

The crystal of the ESP32 board usually does have much worse performance than the TCXO crystal of the Ds3231, so it makes sense (when not using NTP) to update the system (ESP32) time every hour using the DS3231 time. See the example nointernet.toit for this.

All the above are only useful if you have decided the wanted accuracy.
- For a project having NTP(internet) time and we want the RTC for the rare cases the internet is down, do not bother with the aging setting and time drift.
- For projects expecting to be mostly without wifi, the aging correction can be useful, but again 1min error per year can be insignificant for many applications (irrigation timer comes to mind). Usually the calculation of the aging setting is hard to measure correctly and seems (according to internet sources) to be temparature dependend ?
- For projects really isolated (from the internet) and still requiring high time precision, a GNSS module can be a solution (you have to solve other problems of course) . I have created such a driver for tasmota http://gd. For Toit-lang there is already a GNSS driver https:// TODO (not be me) but I have not tested it yet.

## SQW pin
The library does not use/need this pin by itself, but you may find it usefull for other purposes, as interrupt source etc. This library has the following functions to control the SQW output.
```
enable-sqw-1hz
enable-sqw-1kilohz
enable-sqw-4kilohz
enable-sqw-8kilohz
disable-sqw
enable-battery-backed-sqw
disable-battery-backed-sqw
```
These settings will stay active as long as the module is battery backed. 

## ALARM 1/2
Not implemented, does not seem very useful given the ESP32 can wake up from sleep using its own timer.

## Settings not implemented by the driver
if you want to make manipulations not implemented you can use the

> set-bits-with-mask

function. For example

> rtc.set-value-with-mask --register=0x0e --value=0b0_1_000000 --mask=0x0_1_000000

sets only the bit-6 of the register 0x0E and enables battery backed SQW. All other bits are unchanged (dictated by mask)

> rtc.set-bits-with-mask --register=0x0E --bits=0b0_0_000000 --mask=0x0_1_000000

does the oposite.

If this is not enough, there is the rtc.registers object for raw manipulation which is generally ever more error prone than the set-bits function, and basically you bypass the driver.