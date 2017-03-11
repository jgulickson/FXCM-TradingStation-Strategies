--------------------------------------------------------------------------------------------------
------------------------------------------Overview------------------------------------------------
--------------------------------------------------------------------------------------------------
-- Name:             Push Notifications
-- Notes:            Copyright (c) 2016 Jeremy Gulickson
-- Version:          v1.4.07122016
-- Usage:            Receive notifications for a variety of trading based events.
--                   
-- Requirements:     FXTS.Dev (FXCM Trading Station - Development Version) 01.14.062415 or greater
-- Documentation:    http://www.fxcodebase.com/bin/beta/IndicoreSDK-3.0/help/web-content.html
--                   
--------------------------------------------------------------------------------------------------
---------------------------------------Version History--------------------------------------------
--------------------------------------------------------------------------------------------------
-- v1.0.08142015:    *Initial release
--                   Support for trading notifications
--                   Support for test notifications
--                   
-- v1.1.08242015:    *Feature release
--                   Added deposit notifications
--                   Added withdrawal notifications
--                   Added usable margin notifications
--                   Added market status notifications
--                   Added price alert notifications
--                   Substantial code optimization
--                   Removed error checking routines
--                   Renamed to "Push Notifications"
--                   
-- v1.2.08262015     *Feature release
--                   Added margin call status notifications
--                   Added day p/l notifications
--                   Added offer notifications
--                   
-- v1.3.08262015     *Feature release
--                   Added effective leverage notifications 
--                   
-- v1.4.07122016     *Cosmetic release
--                   Usabiliy and verbiage improvements
--                   Separated each notifications type into its own strategy
--                             
--------------------------------------------------------------------------------------------------                                                 
--------------------------------------------------------------------------------------------------
--------------------------------------------------------------------------------------------------


-- Global
local Host = nil;
local Source = nil;
local AccountName = nil;
local Parameters = {};
local PauseToAvoidRaceCondition = false;

-- Deposit & Withdrawal Notifications
local PreviousAccountBalance = nil;
local PreviousAccountUsedMargin = nil;

-- Day P/L Notifications
local TriggeredDayPLCheck = false;
local TriggeredDayPLDayCandle = nil;
local TradingDayOffset = nil;
local TradingWeekOffset = nil;

-- Margin Call Status Notifications
local PreviousMarginCallStatus= nil;
local TimerMarginCallStatus = nil;

-- Usable Margin Notifications
local TriggeredUsableMarginCheck = false;

-- Price Alert Notifications
local TriggeredPriceAlert = false;

-- Price Movement Notifications
local StartPrice = nil;
local StartPriceSet = false;
local TriggeredPriceMovement = false;

-- Market Status Notification
local PreviousMarketStatus = nil;
local TimerMarketStatus = nil;

-- Effective Leverage Notification
local PreviousEffectiveLeverage = nil;

-- Test Notifications
local TimerTest = nil;


function Init()
    strategy:name("Notifications");
    strategy:description("Receive notifications for a variety of trading based events.");
	strategy:type(core.Signal);
	
	strategy.parameters:addGroup("Configuration");
	strategy.parameters:addString("SelectedAccount", "Account Number", "Select the account to monitor.", "");
	strategy.parameters:setFlag("SelectedAccount", core.FLAG_ACCOUNT);
	strategy.parameters:addString("NotificationType", "Notification Type", "'Alert' will appear as a pop-up. 'Trace' will appear in the 'Log' tab of the 'Events' window in FXTS or in the 'Actions' tab in TSMobile.", "3");
	strategy.parameters:addStringAlternative("NotificationType", "Alert", "", "1");
	strategy.parameters:addStringAlternative("NotificationType", "Trace", "", "2");
	strategy.parameters:addStringAlternative("NotificationType", "Both", "", "3");
	
	strategy.parameters:addGroup("Trading Activity Notifications");
	strategy.parameters:addBoolean("TradeOpen", "Trade Opened", "Receive notifications when opening a trade.", true);
	strategy.parameters:addBoolean("TradeClose", "Trade Closed", "Receive notifications when closing a trade.", true);
	strategy.parameters:addBoolean("OrderPending", "Order Pending", "Receive notifications when creating a pending order.", true);
	
	strategy.parameters:addGroup("Deposit & Withdrawal Notifications");
	strategy.parameters:addBoolean("Deposit", "Deposit", "Receive notifications when depositing funds via deposits, rollover credits, positive trade adjustments, etc.", true);
	strategy.parameters:addBoolean("Withdrawal", "Withdrawal", "Receive notifications when withdrawing funds via withdrawals, rollover debits, negative trade adjustments, etc.", true);
	
	strategy.parameters:addGroup("Day P/L Notifications");
	strategy.parameters:addBoolean("DayPL", "Day P/L", "Receive notifications when Day P/L reaches a specified positive or negative value.", false);
	strategy.parameters:addInteger("DayPLThreshold", "Threshold Value", "Threshold value for Day P/L in base currency.", 100, 0, 100000000);
	
	strategy.parameters:addGroup("Effective Leverage Notifications");
	strategy.parameters:addBoolean("EffectiveLeverage", "Effective Leverage", "Receive notifications on effective leverage at specified intervals.", true);
	strategy.parameters:addInteger("EffectiveLeverageTimerDelay", "Delay", "Time in seconds between effective leverage notifications.", 3600, 0, 86400);
	
    strategy.parameters:addGroup("Margin Call Status Notifications");
	strategy.parameters:addBoolean("MarginCallStatus", "Margin Call Status", "Receive notifications when margin call status changes.", true);
	strategy.parameters:addInteger("MarginCallStatusTimerDelay", "Delay", "Time in seconds between margin call status checks.", 60, 0, 3600);
	
	strategy.parameters:addGroup("Usable Margin Threshold Notifications");
	strategy.parameters:addBoolean("UsableMarginCheck", "Usable Margin Check", "Receive notifications when breaching a specified value of usable margin.", false);
	strategy.parameters:addInteger("UsableMarginThreshold", "Threshold Value", "Threshold value for usable margin breach in base currency.", 1000, 0, 100000000);
	
	strategy.parameters:addGroup("Price Alert Notifications");
	strategy.parameters:addBoolean("PriceAlert", "Price Alert", "Receive notifications when a specified symbol reaches a specified Bid price.", false);
	strategy.parameters:addDouble("PriceAlertRate", "Rate", "Enter the price to monitor.", 0);
	strategy.parameters:setFlag("PriceAlertRate", core.FLAG_PRICE);
	
	strategy.parameters:addGroup("Price Movement Notifications");
	strategy.parameters:addBoolean("PriceMovement", "Price Movement", "Receive notifications when a specified symbol changes a specified number of pips.", true);
	strategy.parameters:addInteger("PriceMovementThreshold", "Threshold", "Threshold value for symbol change in pips.", 10, 1, 10000);
	
	strategy.parameters:addGroup("Market Status Notifications");
	strategy.parameters:addBoolean("MarketStatus", "Market Status", "Receive notifications when a specified symbol opens or closes for trading.", false);
	strategy.parameters:addInteger("MarketStatusTimerDelay", "Delay", "Time in seconds between market status checks.", 60, 0, 3600);
	
	strategy.parameters:addGroup("Test Notifications");
	strategy.parameters:addBoolean("TestTimer", "Test Notification", "Receive a test notifications every xx seconds.", false);
	strategy.parameters:addInteger("TestTimerDelay", "Delay", "Time in seconds between test notifications.", 10, 0, 86400);
end


function Prepare()
	Parameters.SelectedAccount = instance.parameters.SelectedAccount;
	Parameters.NotificationType = instance.parameters.NotificationType;
	Parameters.TradeOpen = instance.parameters.TradeOpen;
	Parameters.TradeClose = instance.parameters.TradeClose;
	Parameters.OrderPending = instance.parameters.OrderPending;
	Parameters.Deposit = instance.parameters.Deposit;
	Parameters.Withdrawal = instance.parameters.Withdrawal;
	Parameters.DayPL = instance.parameters.DayPL;
	Parameters.DayPLThreshold = instance.parameters.DayPLThreshold;
	Parameters.EffectiveLeverage = instance.parameters.EffectiveLeverage;
	Parameters.EffectiveLeverageTimerDelay = instance.parameters.EffectiveLeverageTimerDelay;
	Parameters.MarginCallStatus = instance.parameters.MarginCallStatus;
	Parameters.MarginCallStatusTimerDelay = instance.parameters.MarginCallStatusTimerDelay;
	Parameters.UsableMarginCheck = instance.parameters.UsableMarginCheck;
	Parameters.UsableMarginThreshold = instance.parameters.UsableMarginThreshold;
	Parameters.PriceAlert = instance.parameters.PriceAlert;
	Parameters.PriceAlertRate = instance.parameters.PriceAlertRate;
	Parameters.PriceMovement = instance.parameters.PriceMovement;
	Parameters.PriceMovementThreshold = instance.parameters.PriceMovementThreshold;
	Parameters.MarketStatus = instance.parameters.MarketStatus;
	Parameters.MarketStatusTimerDelay = instance.parameters.MarketStatusTimerDelay;
	Parameters.TestTimer = instance.parameters.TestTimer;
	Parameters.TestTimerDelay = instance.parameters.TestTimerDelay;
	
	Host = core.host;
	Source = instance.bid;

	-- AccountName doesn't drop leading numbers (database specific) whereas AccountID does.
	-- User will be familiar with AccountName but not likely AccountID.
	AccountName = Host:findTable("accounts"):find("AccountID", Parameters.SelectedAccount).AccountName 
	instance:name("Notifications");

	-- Sets default values
	PreviousAccountBalance = Host:findTable("accounts"):find("AccountID", Parameters.SelectedAccount).Balance;
	PreviousAccountUsedMargin = Host:findTable("accounts"):find("AccountID", Parameters.SelectedAccount).UsedMargin;
	
	if Parameters.OrderPending then 
		Host:execute("subscribeTradeEvents", 1, "orders");
	end
	-- Parameters.Deposit or Parameters.Withdrawal are checked as these functions update
	-- PreviousAccountBalance and PreviousAccountUsedMargin values
	if Parameters.TradeOpen or Parameters.TradeClose or Parameters.Deposit or Parameters.Withdrawal then
		Host:execute("subscribeTradeEvents", 2, "trades");
	end
	if Parameters.EffectiveLeverage then
		EffectiveLeverageTimer = Host:execute("setTimer", 6, Parameters.EffectiveLeverageTimerDelay);
	end
	if Parameters.MarginCallStatus then
		PreviousMarginCallStatus = Host:findTable("accounts"):find("AccountID", Parameters.SelectedAccount).MarginCall;
		TimerMarginCallStatus = Host:execute("setTimer", 3, Parameters.MarginCallStatusTimerDelay);
	end
	if Parameters.MarketStatus then
		PreviousMarketStatus = Host:execute("getTradingProperty", "marketStatus", Source:instrument(), nil);
		TimerMarketStatus = Host:execute("setTimer", 4, Parameters.MarketStatusTimerDelay);
	end
	if Parameters.TestTimer then
		TimerTest = Host:execute("setTimer", 5, Parameters.TestTimerDelay);
	end
	
	TradingDayOffset = Host:execute("getTradingDayOffset");
    TradingWeekOffset = Host:execute("getTradingWeekOffset");
end


function Update()
	if Parameters.PriceAlert and not TriggeredPriceAlert then
		CheckPrice(Source:instrument(), Parameters.PriceAlertRate, Parameters.NotificationType);
	end
	if Parameters.PriceMovement and not TriggeredPriceMovement then
		if not StartPriceSet then
			StartPrice = Source:tick(Source:size() - 1);
			StartPriceSet = true;
		end
		CheckMovement(Source:instrument(), StartPrice, Source:tick(Source:size() - 1), Source:pipSize(), Parameters.PriceMovementThreshold, Parameters.NotificationType);
	end
	
	-- No "SubscribeEvents" host command exists for account table updates, so this simply checks every price update.
	-- Likely a more efficient way exists to accomplish this besides simply using a timer.
	if Parameters.Deposit or Parameters.Withdrawal then
		CheckBalance(Parameters.SelectedAccount, Parameters.NotificationType);
	end
	if Parameters.DayPL and not TriggeredDayPLCheck then
		CheckDayPL(Parameters.SelectedAccount, Parameters.DayPLThreshold, Parameters.NotificationType);
	elseif Parameters.DayPL and TriggeredDayPLCheck then
		-- Once triggered store the current trading day.
		if TriggeredDayPLDayCandle == nil then
			TriggeredDayPLDayCandle = core.getcandle("D1", core.now(), TradingDayOffset, TradingWeekOffset);
		-- Reset "TriggeredDayPLCheck" once a new Daily candle is created; i.e. at 17:00 ET.
		elseif core.getcandle("D1", core.now(), TradingDayOffset, TradingWeekOffset) > TriggeredDayPLDayCandle and core.dateToTable(core.now()).hour > 17 then
			TriggeredDayPLDayCandle = core.getcandle("D1", core.now(), TradingDayOffset, TradingWeekOffset);
			TriggeredDayPLCheck = false;
		end
	end
	if Parameters.UsableMarginCheck and not TriggeredUsableMarginCheck then
		CheckMargin(Parameters.SelectedAccount, Parameters.UsableMarginThreshold, Parameters.NotificationType);
	end
end


function FindOrder(OrderID, AccountID, NotificationType)	
	PauseToAvoidRaceCondition = true;
	local EntryOrderTypes = "SE, LE, RE, STE, LTE, RTE";
	local OrdersTable = Host:findTable("orders");
	local Order = nil;
	
	if OrdersTable:find("OrderID", OrderID) ~= nil then
		Order = OrdersTable:find("OrderID", OrderID);
		-- The below doesn't work as expected?
		-- if Order.IsEntryOrder then
		if string.match(EntryOrderTypes, Order.Type) ~= nil then
			if Order.AccountID == AccountID then
				-- Buy 10K EURUSD @ 1.50000 pending on account 12345.
				local OrderMessage = FormatDirection(Order.BS) .. " " .. Order.AmountK .. "K " .. Order.Instrument .. " @ " .. Order.Rate .. " pending on account " .. AccountName .. ". ";
				SendNotification(NotificationType, Order.Instrument, Order.Rate, OrderMessage, Order.Time);
			end
		end
	end
	PauseToAvoidRaceCondition = false;
end


function FindTrade(TradeID, AccountID, NotificationType)
	PauseToAvoidRaceCondition = true;
	local Account = Host:findTable("accounts"):find("AccountID", AccountID);
	local ClosedTradesTable = Host:findTable("closed trades");
	local TradesTable = Host:findTable("trades");
	local Trade = nil;
	
	if ClosedTradesTable:find("TradeID", TradeID) ~= nil then
		if Parameters.TradeClose then
			Trade = ClosedTradesTable:find("TradeID", TradeID);
			if Trade.AccountID == AccountID then
				-- Buy 10K EURUSD opened @ 1.50000; closed @ 1.60000; gross PL of $25.00 on account 12345.
				local ClosedTradeMessage = FormatDirection(Trade.BS) .. " " .. Trade.AmountK .. "K " .. Trade.Instrument .. " opened @ " .. Trade.Open .. "; closed @ " .. Trade.Close .. "; gross PL of " .. FormatFinancial(Trade.GrossPL, 2) .. " on account " .. AccountName .. ". ";
				SendNotification(NotificationType, Trade.Instrument, Trade.Close, ClosedTradeMessage, Trade.CloseTime);
			end
		end
	elseif TradesTable:find("TradeID", TradeID) ~= nil then
		if Parameters.TradeOpen then		
			Trade = TradesTable:find("TradeID", TradeID);
			if Trade.AccountID == AccountID then
				-- Buy 10K EURUSD opened @ 1.50000 on account 12345.
				local OpenTradeMessage = FormatDirection(Trade.BS) .. " " .. Trade.AmountK .. "K " .. Trade.Instrument .. " opened @ " .. Trade.Open .. " on account " .. AccountName .. ". ";
				SendNotification(NotificationType, Trade.Instrument, Trade.Open, OpenTradeMessage, Trade.Time);
			end
		end
	end
	PreviousAccountBalance = Account.Balance;
	PreviousAccountUsedMargin = Account.UsedMargin;
	PauseToAvoidRaceCondition = false;
end


function CheckBalance(AccountID, NotificationType)
	local AccountsTable = Host:findTable("accounts");
	local Account = nil;
	
	while PauseToAvoidRaceCondition do
		-- Done do avoid a race condition between FindTrade()/FindOrder() function triggering due to trading
		-- and a price update triggering CheckBalance()
	end
	
	if AccountsTable:find("AccountID", AccountID) ~= nil then
		Account = AccountsTable:find("AccountID", AccountID);
		if PreviousAccountBalance ~= Account.Balance then
			-- Assumption here is that if usable margin is the same but balance is different then
			-- the change in balance must be due to a non trading activity
			if PreviousAccountUsedMargin == Account.UsedMargin then
				local AccountBalanceChange = Account.Balance - PreviousAccountBalance;
				local AccountMessage = nil;
				if AccountBalanceChange > 0 then
					if Parameters.Deposit then
						-- 50 deposit made to account 12345.
						AccountMessage = FormatFinancial(AccountBalanceChange, 2) .. " deposit made to account " .. AccountName .. ". ";
						SendNotification(NotificationType, 0, 0, AccountMessage, core.now());
					end
				else
					if Parameters.Withdrawal then
						-- 50 withdrawal made to account 12345.
						AccountMessage = FormatFinancial(AccountBalanceChange, 2) .. " withdrawal made to account " .. AccountName .. ". ";
						SendNotification(NotificationType, 0, 0, AccountMessage, core.now());
					end
				end
			end
			PreviousAccountBalance = Account.Balance;
		end
	end
end


function CheckMargin(AccountID, ThresholdValue, NotificationType)
	local AccountsTable = Host:findTable("accounts");
	local Account = nil;
	
	if AccountsTable:find("AccountID", AccountID) ~= nil then
		Account = AccountsTable:find("AccountID", AccountID);
		if Account.UsableMargin < ThresholdValue then
			-- Only want this alert triggered once.
			TriggeredUsableMarginCheck = true;
			-- Usable margin on account 12345 has exceeded threshold value of 50; current value is $100.
			local MarginMessage = "Usable Margin on account " .. AccountName .. " has exceeded threshold value of " .. FormatFinancial(ThresholdValue, 2) .. "; current value is " .. FormatFinancial(Account.UsableMargin, 2) .. ". ";
			SendNotification(NotificationType, 0, 0, MarginMessage, core.now());
		end
	end	
end


function CheckTimer(Delay, NotificationType)
	local TimerMessage = "Timer set to " .. Delay .. " seconds has triggered. ";
	SendNotification(NotificationType, 0, 0, TimerMessage, core.now());
end


function CheckMarketStatus(Symbol, NotificationType)
	local Status = Host:execute("getTradingProperty", "marketStatus", Symbol, nil);
	
	if Status ~= PreviousMarketStatus then
		PreviousMarketStatus = Status;
		local MarketMessage = nil; 
		if Status then
			MarketMessage = "Trading has opened for " .. Symbol .. ". ";
		else
			MarketMessage = "Trading has closed for " .. Symbol .. ". ";
		end
		SendNotification(NotificationType, Symbol, 0, MarketMessage, core.now());
	end
end


function CheckMarginCall(AccountID, NotificationType)
	local AccountsTable = Host:findTable("accounts");
	local Account = nil;
	
	if AccountsTable:find("AccountID", AccountID) ~= nil then
		Account = AccountsTable:find("AccountID", AccountID);
		if Account.MarginCall ~= PreviousMarginCallStatus then
			PreviousMarginCallStatus = Account.MarginCall;
			-- Margin Call status on account 12345 has changed from 'No' to 'Warning'.
			local MarginCallMessage = "Margin Call status on " .. AccountName .. " has changed from '" .. FormatMarginCallStatus(PreviousMarginCallStatus) .. "' to '" .. FormatMarginCallStatus(Account.MarginCall) .. "'. ";
			SendNotification(NotificationType, 0, 0, MarginCallMessage, core.now());
		end
	end
end


function CheckPrice(Symbol, Rate, NotificationType)
	if Source:size() - 1 > Source:first() then
		if core.crossesOverOrTouch(Source, Rate, tick) then
			-- Only want this alert triggered once.
			TriggeredPriceAlert = true;
			-- Price alert for EURUSD @ 1.5000 has triggered.
			local PriceMessage = "Price alert for " .. Symbol .. " @ " .. Rate .. " has triggered. ";
			SendNotification(NotificationType, Symbol, Rate, PriceMessage, core.now());
		end
	end
end


function CheckMovement(Symbol, StartRate, CurrentRate, PipSize, ThresholdValue, NotificationType)
	if math.abs(StartRate - CurrentRate) > (ThresholdValue * PipSize) then
		-- Only want this alert triggered once.
		TriggeredPriceMovement = true;
		-- Price movement for EURUSD 10 pips has triggered.
		local MovementMessage = "Price movement for a " .. Symbol .. " " .. ThresholdValue .. " pip move has triggered. ";
		SendNotification(NotificationType, Symbol, CurrentRate, MovementMessage, core.now());
	end
end


function CheckDayPL(AccountID, ThresholdValue)
	local AccountsTable = Host:findTable("accounts");
	local Account = nil;
	
	if AccountsTable:find("AccountID", AccountID) ~= nil then
		Account = AccountsTable:find("AccountID", AccountID);
		if Account.DayPL >= ThresholdValue then
			-- Only want this alert triggered once.
			TriggeredDayPLCheck = true;
			-- Day P/L on account 12345 has exceeded threshold value of $50; current value is $100.
			local DayPLMessage = "Day P/L on " .. AccountName .. " has exceeded threshold value of " .. FormatFinancial(ThresholdValue, 2) .. "; current value is " .. FormatFinancial(Account.DayPL, 2) .. ". ";
			SendNotification(NotificationType, 0, 0, DayPLMessage, core.now());
		end
	end
end


function CheckEffectiveLeverage(AccountID, NotificationType)
	-- Only accurate for FX symbols
	local Account = {};
	local Trade = {};
	local Offer = {};
	local EffectiveLeverage = nil;
	
	Account.Table = Host:findTable("accounts");
	Trade.Table = Host:findTable("trades"):enumerator();
	Offer.Table = Host:findTable("offers");
	
	Account.Row = Account.Table:find("AccountID", AccountID);
	Trade.Row = Trade.Table:next();
	Trade.SumInUSD = 0;
	Trade.Count = 0;
	while Trade.Row ~= nil do
		if Trade.Row.AccountID == AccountID and Offer.Table:find("Instrument", Trade.Row.Instrument).InstrumentType == 1 then
			Trade.SizeInUSD = ConvertToUSD(Offer.Table:find("Instrument", Trade.Row.Instrument).ContractCurrency, Trade.Row.Lot);
			Trade.SumInUSD = Trade.SumInUSD + Trade.SizeInUSD;
		end
		Trade.Row = Trade.Table:next();
	end
	EffectiveLeverage = Trade.SumInUSD / Account.Row.Equity;
	local EffectiveLeverageMessage = "Effective leverage on account " .. AccountName .. " is currently " .. FormatPrecision(EffectiveLeverage, 2) .. ":1. ";
	SendNotification(NotificationType, 0, 0, EffectiveLeverageMessage, core.now());
end


--------------------------------------------------------------------------------------------------
---------------------------------------Common Functions-------------------------------------------
--------------------------------------------------------------------------------------------------


function FormatDirection(BuySell)
	local Directon = nil;
	
	if BuySell == "B" then
		Direction = "Buy";
	elseif BuySell == "S" then
		Direction = "Sell";
	else
		Direction = "-";
	end
	return Direction;
end


function FormatMarginCallStatus(Code)
	local Status = nil;
	
	if Code == "Y" then
		Status = "Yes";
	elseif Code == "W" then
		Status = "Warning";
	elseif Code == "Q" then
		Status = "Equity Stop";
	elseif Code == "A" then
		Status = "Equity Alert";
	elseif Code == "N" then
		Status = "No";
	else
		Status = "-";
	end
	return Status;
end


function FormatFinancial(Number, Precision)
	-- Inspired by http://www.gammon.com.au/forum/?id=7805
	
	Number = string.format("%." .. Precision .. "f", Number);
	
	local Result = "";
	local Sign, Before, After = string.match (tostring (Number), "^([%+%-]?)(%d*)(%.?.*)$")
	while string.len (Before) > 3 do
		Result = "," .. string.sub (Before, -3, -1) .. Result
		Before = string.sub (Before, 1, -4)
	end
	return Sign .. "$" .. Before .. Result .. After;
end


function FormatPrecision(Number, Precision)
	return string.format("%." .. Precision .. "f", Number);
end


function ConvertToUSD(BaseCurrency, Amount)
	-- Only accurate for USD denominated accounts.
	local OfferTable = Host:findTable("offers");
	local SizeInUSD = 0;
	
	if BaseCurrency == "EUR" then SizeInUSD = Amount * OfferTable:find("Instrument", "EUR/USD").Bid;
	elseif BaseCurrency == "USD" then SizeInUSD = Amount;
	elseif BaseCurrency == "GBP" then SizeInUSD = Amount * OfferTable:find("Instrument", "GBP/USD").Bid;
	elseif BaseCurrency == "AUD" then SizeInUSD = Amount * OfferTable:find("Instrument", "AUD/USD").Bid;
	elseif BaseCurrency == "NZD" then SizeInUSD = Amount * OfferTable:find("Instrument", "NZD/USD").Bid;
	elseif BaseCurrency == "CAD" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/CAD").Bid);
	elseif BaseCurrency == "CHF" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/CHF").Bid);
	elseif BaseCurrency == "HKD" then SizeInUSD = amount * (1 / OfferTable:find("Instrument", "USD/HKD").Bid);
	elseif BaseCurrency == "JPY" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/JPY").Bid);
	elseif BaseCurrency == "NOK" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/NOK").Bid);
	elseif BaseCurrency == "SEK" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/SEK").Bid);
	elseif BaseCurrency == "SGD" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/SGD").Bid);
	elseif BaseCurrency == "TRY" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/TRY").Bid);
	elseif BaseCurrency == "ZAR" then SizeInUSD = Amount * (1 / OfferTable:find("Instrument", "USD/ZAR").Bid);
	else error("Base Currency Conversion Path Does Not Exist");
	end
	return SizeInUSD;
end


function SendNotification(Type, Symbol, Rate, Message, Time)
	if Type == "1" then
		terminal:alertMessage(Symbol, Rate, Message, Time);
	elseif Type == "2" then
		Host:trace(Message);
	else
		terminal:alertMessage(Symbol, Rate, Message, Time);
		Host:trace(Message);
	end
end


function AsyncOperationFinished(Reference, Success, Message, Message2, Message3)
	if Reference == 1 then
		-- Only continue if order is waiting.
		-- Done to prohibit messages for each order status update.
		if Message2  == "W" then
			FindOrder(Message, Parameters.SelectedAccount, Parameters.NotificationType);
		end
	elseif Reference == 2 then
		FindTrade(Message, Parameters.SelectedAccount, Parameters.NotificationType);
	elseif Reference == 3 then
		CheckMarginCall(Parameters.SelectedAccount, Parameters.NotificationType);
	elseif Reference == 4 then
		CheckMarketStatus(Source:instrument(), Parameters.NotificationType);
	elseif Reference == 5 then
		CheckTimer(Parameters.TestTimerDelay, Parameters.NotificationType);
	elseif Reference == 6 then
		CheckEffectiveLeverage(Parameters.SelectedAccount, Parameters.NotificationType);
	end
end


function ReleaseInstance()
	Host:execute("killTimer", EffectiveLeverageTimer);
	Host:execute("killTimer", TimerMarketStatus);
	Host:execute("killTimer", TimerMarginCallStatus);
	Host:execute("killTimer", TimerTest);
end