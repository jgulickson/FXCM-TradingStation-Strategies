# FX-TradingStation-Strategies

## Overview
#### Summary
Repository contains two (2) non-trading strategies written in Lua and intended to be executed using [FXCM Trading Station](https://www.fxcm.com/uk/platforms/trading-station/innovative-platform/); both were originally created as proof of concepts. FXCM Trading Station is a financial trading application written for Windows that can leverage scripts written in Lua (and JavaScript) via [Indicore SDK](http://www.fxcodebase.com/bin/products/IndicoreSDK/3.3.0/help/Lua/web-content.html) to further extend functionality.

###### Hue Lights Control
Proof of concept to control [Philips Hue](http://www2.meethue.com/en-us/) Lights based on trading activity.

###### Push Notifications
Proof of concept to facilitate of push notifications for trading, account and offer activity.

## **Installation**
1. Clone or download desired *.lua files from this repository.

2. Move *.lua files to the following directory depending on 32 or 64 bit OS version:

	`C:\Program Files (x86)\Candleworks\FXTS2\strategies\Custom`

	`C:\Program Files\Candleworks\FXTS2\strategies\Custom`

3. If previously running, close and reopen FXCM Trading Station.

4. Strategy(ies) will now be available under 'Alerts and Trading Automation' > 'New Strategy or Alert.'

*OR*

1. Clone or download desired *.lua files from this repository.

2. If not running, open FXCM Trading Station.

3. Drap and drop *.lua files onto a Marketscope chart instance.

## Version History

#### Hue Lights Control
###### 1.0.03092015
- ***Initial release***

#### Push Notifications
###### 1.0.08142015
- ***Initial release***
- Support for trading notifications
- Support for test notifications

###### 1.1.08242015
- ***Feature release***
- Added deposit notifications
- Added withdrawal notifications
- Added usable margin notifications
- Added market status notifications
- Added price alert notifications
- Substantial code optimization
- Removed error checking routines
- Renamed to "Push Notifications"

###### 1.2.08262015
- ***Feature release***
- Added margin call status notifications
- Added day p/l notifications
- Added offer notifications
            
###### 1.3.08262015
- ***Feature release***
- Added effective leverage notifications 
                  
###### 1.4.07122016
- ***Cosmetic release***
- Usabiliy and verbiage improvements
