---------------------------------------- Overview ------------------------------------------
-- Name:                  FXCM To Oanda Trade Copier
-- Notes:                 Copyright (c) 2017 Jeremy Gulickson
-- Version:               1.4.03192017
-- Format:                major.minor.mmddyyyy
-- 
-- Usage:                 Designed to copy postion(s) from an FXCM account to an Oanda account.
--                        FXCM postions are sourced from FXTS directly and Oanda positions verified
--                        and modified via RESTful API queries.
--
-- Software Requirements: FXTS (FXCM Trading Station)
--                        http_lua.dll
--                        JSON.lua -> http://regex.info/blog/lua/json
--
-- Account Requirements:  FXCM: N/A.
--                        Oanda: Account must be type v20.
--
-- FXCM Documentation:    http://www.fxcodebase.com/bin/products/IndicoreSDK/3.1.0/help/Lua/web-content.html
-- Oanda Documentation:   http://developer.oanda.com/rest-live-v20/introduction/
--
-------------------------------------- Version History -------------------------------------
-- v1.0.01302017:         -> Initial release; proof of concept.
--
-- v1.1.02022017:         -> Performance improvements and cosmetic code updates.
--                        -> Added ParseResponse() function to parse LUA tables for eventual
--                             validation of responses from Oanda.
--                        -> Added CreatePriceBounds() function to use in CreateOrder() to
--                             support Oanda's priceBounds parameter (FXCM's market
--                             range equivalent).
--                        -> Added PositionCheck() function; currently not functional.
--                        -> Updated log method for improved troubleshooting.  Went from
--                             'Host:trace' to a custom 'WriteToLog:debug' funtion.
--
-- v1.2.02032017:         -> Completed PositionCheck() function, now functional.
--
-- v1.3.02272017:         -> Added email notifications.
--
-- v1.4.03192017:         -> Cosmetic clean up; removed hardcoded values to make Github ready.
--
--------------------------------------------------------------------------------------------


--------------------------------------------------------------------------------------------
-- Global Variable Setup
--------------------------------------------------------------------------------------------

-- Require LUA extension to support HTTPS protocol
require("http_lua");

-- Global strategy variables
local Host = nil;
local StopStrategy = false;

-- Global Oanda variables
local Oanda = {};
Oanda.DemoSubdomain = "api-fxpractice.oanda.com";
Oanda.RealSubdomain = "api-fxtrade.oanda.com";
Oanda.Subdomain = nil;
Oanda.APIToken = nil;
Oanda.AccountType = nil;
Oanda.AccountID = nil;
Oanda.AllowedSlippageInPips = nil;
Oanda.MaxOrderAttempts = nil;
Oanda.MaxPostionCheckAttempts= nil;

-- Global FXCM variables
local FXCM = {};
FXCM.AccountID = nil;
FXCM.SendEmail = nil;
FXCM.EmailAddress = nil;
	
-- Global Timer variables
local Timer = {};
Timer.HealthCheck = nil;
Timer.SendRequest = nil;
Timer.PositionCheckInterval = nil;
Timer.PositionCheckNew = nil;

--------------------------------------------------------------------------------------------
-- Initialize Function
--------------------------------------------------------------------------------------------

function Init()
    strategy:name("FXCM To Oanda Trade Copier");
    strategy:type(core.Both);
	
	strategy.parameters:addGroup("FXCM Related");
	strategy.parameters:addString("FXCMAccountID", "Account ID", "Enter the FXCM account id to monitor.", "");
	strategy.parameters:setFlag("FXCMAccountID", core.FLAG_ACCOUNT);
	
	strategy.parameters:addGroup("Oanda Related");
	strategy.parameters:addString("AccountType", "Account Type", "Select the Oanda account type.", "Demo")
	strategy.parameters:addStringAlternative("AccountType", "Demo", "", "Demo");
	strategy.parameters:addStringAlternative("AccountType", "Real", "", "Real");
    strategy.parameters:addString("APIToken", "API Token", "Enter the Oanda API token.", "");
	strategy.parameters:addString("OandaAccountID", "Account ID", "Enter the Oanda account id to trade.", "");
	strategy.parameters:addDouble("AllowedSlippageInPips", "Allowed Slippage Range", "Enter allowed slippage in pips.", 5, 0, 100);
	strategy.parameters:addInteger("MaxOrderAttempts", "Maximum Order Attempts", "Enter the maximum attempts to resend an order before stopping the stratey.", 5, 0, 10);
	strategy.parameters:addInteger("MaxPostionCheckAttempts", "Maximum Position Check Attempts", "Enter the maximum position check attempts before stopping the stratey.", 5, 0, 10);
	
	strategy.parameters:addGroup("Notification Related");
	strategy.parameters:addBoolean("SendEmail", "Send Email", "Send an email if strategy fails.", false);
	strategy.parameters:addString("EmailAddress", "Email Address", "Enter the recipient address to email.", "");
	strategy.parameters:setFlag("EmailAddress", core.FLAG_EMAIL);
	
	strategy.parameters:addGroup("Risk Related");
	strategy.parameters:addBoolean("RunHealthCheck", "Health Check", "Perform a health check on startup.", true);
	strategy.parameters:addBoolean("PositionCheck", "Position Check", "Perform a postion check between brokers at set intervals.", true);
	strategy.parameters:addInteger("PositionCheckInterval", "Positions Check Interval", "Enter time between positions checks in minutes.", 5, 0, 60);
	
	strategy.parameters:addGroup("Log Related");
	strategy.parameters:addInteger("LogLevel", "Log Level", "Determines what informaton to write to an external log.", 0);
	strategy.parameters:addIntegerAlternative("LogLevel", "Off", "", 0);
	strategy.parameters:addIntegerAlternative ("LogLevel", "Error", "", 1);
	strategy.parameters:addIntegerAlternative("LogLevel", "Info", "", 2);
	strategy.parameters:addIntegerAlternative("LogLevel", "Debug", "", 3);
end


--------------------------------------------------------------------------------------------
-- Prepare Function
--------------------------------------------------------------------------------------------

function Prepare()
    Host = core.host;
	
	Oanda.AccountType = instance.parameters.AccountType;
	Oanda.APIToken =  instance.parameters.APIToken;
	Oanda.AccountID =  instance.parameters.OandaAccountID;
	FXCM.AccountID =  instance.parameters.FXCMAccountID;
	if Oanda.AccountType == "Real" then
		Oanda.Subdomain = Oanda.RealSubdomain;
	else
		Oanda.Subdomain = Oanda.DemoSubdomain;
	end
	Oanda.AllowedSlippageInPips = instance.parameters.AllowedSlippageInPips;
	Oanda.MaxOrderAttempts = instance.parameters.MaxOrderAttempts;
	Oanda.MaxPostionCheckAttempts = instance.parameters.MaxPostionCheckAttempts;
	FXCM.SendEmail = instance.parameters.SendEmail;
	FXCM.EmailAddress = instance.parameters.EmailAddress;
	
	WriteToLog = Logger:create("Marketscope-Log", instance.parameters.LogLevel);
	instance:name("FXCM (" .. FXCM.AccountID .. ") to Oanda (" .. Oanda.AccountID .. ")");
	if instance.parameters.RunHealthCheck then Timer.HealthCheck = Host:execute("setTimer", 100, 2) end
	if instance.parameters.PositionCheck then Timer.PositionCheckInterval = Host:execute("setTimer", 200, instance.parameters.PositionCheckInterval * 60) end
	Host:execute("subscribeTradeEvents", 300, "trades");
	
	WriteToLog:debug("Prepare() <<<<< FINISHED <<<<< FINISHED <<<<<");
end

--------------------------------------------------------------------------------------------
-- Update Function
--------------------------------------------------------------------------------------------

function Update()
	--Not Employed
end


--------------------------------------------------------------------------------------------
-- Health Check Function
--------------------------------------------------------------------------------------------

function HealthCheck(oInstrument)
	WriteToLog:info("HealthCheck() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zURL = nil;
	local zRequestReponse = nil;
	local zPass = nil;
	
	WriteToLog:debug("FXCM Account ID: ".. FXCM.AccountID);
	WriteToLog:debug("Oanda API Token: " .. Oanda.APIToken);
	WriteToLog:debug("Oanda Account ID: " .. Oanda.AccountID);

	local zPass = true;
	
	-- Get Accounts
	zURL = CreateURLSyntax("Account", "GET_Accounts", Oanda.Subdomain, Oanda.AccountID, nil, nil, nil);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if string.match(zRequestReponse, "accounts") ~= nil and string.match(zRequestReponse, "tags") ~= nil then
		WriteToLog:debug("HealthCheck() | GET_Accounts Passed");
	else
		WriteToLog:error("HealthCheck() | GET_Accounts Failed");
		zPass = false;
	end
	ParseResponse("GET_Accounts", DecodeResponse(zRequestReponse));
	
	-- Get Account
	zURL = CreateURLSyntax("Account", "GET_Account", Oanda.Subdomain, Oanda.AccountID, nil, nil, nil);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if string.match(zRequestReponse, "account") ~= nil and string.match(zRequestReponse, "pendingOrderCount") ~= nil then
		WriteToLog:debug("HealthCheck() | GET_Account Passed");
	else
		WriteToLog:error("HealthCheck() | GET_Account Failed");
		zPass = false;
	end
	ParseResponse("GET_Account", DecodeResponse(zRequestReponse));
	
	-- Get Open Positions
	zURL = CreateURLSyntax("Positions", "GET_OpenPositions", Oanda.Subdomain, Oanda.AccountID, nil, nil, nil);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if string.match(zRequestReponse, "positions") ~= nil and string.match(zRequestReponse, "lastTransactionID") ~= nil then
		WriteToLog:debug("HealthCheck() | GET_OpenPositions Passed");
	else
		WriteToLog:error("HealthCheck() | GET_OpenPositions Failed");
		zPass = false;
	end
	ParseResponse("GET_OpenPositions", DecodeResponse(zRequestReponse));
	
	-- Get Pricing
	zURL = CreateURLSyntax("Pricing", "GET_Pricing", Oanda.Subdomain, Oanda.AccountID, nil, nil, oInstrument);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if string.match(zRequestReponse, "prices") ~= nil and string.match(zRequestReponse, "quoteHomeConversionFactors") ~= nil then
		WriteToLog:debug("HealthCheck() | GET_Pricing Passed");
	else
		WriteToLog:error("HealthCheck() | GET_Pricing Failed");
		zPass = false;
	end
	ParseResponse("GET_Pricing", DecodeResponse(zRequestReponse));
	
	-- Get Instruments
	zURL = CreateURLSyntax("Account", "GET_Instruments", Oanda.Subdomain, Oanda.AccountID, nil, nil, oInstrument);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if string.match(zRequestReponse, "displayPrecision") ~= nil and string.match(zRequestReponse, "minimumTrailingStopDistance") ~= nil then
		WriteToLog:debug("HealthCheck() | GET_Instruments Passed");
	else
		WriteToLog:error("HealthCheck() | GET_Instruments Failed");
		zPass = false;
	end
	ParseResponse("GET_Instruments", DecodeResponse(zRequestReponse));

	if zPass then
		WriteToLog:debug("HealthCheck() <<<<< FINISHED <<<<< FINISHED <<<<<");
		SendNotification("Trace", oInstrument, 0, "HealthCheck() Successful | Strategy OK", core.now());
		SendNotification("StartEmail", oInstrument, 0, "HealthCheck() Successful | Strategy OK", core.now());
	else
		WriteToLog:error("HealthCheck() Failed");
		SendNotification("All", oInstrument, 0, "HealthCheck() Failed | Strategy Stopped", core.now());
		StopStrategy = true;
	end
end


--------------------------------------------------------------------------------------------
-- Position Check Function
--------------------------------------------------------------------------------------------

function PositionCheck(oInstrument)
	WriteToLog:info("PositionCheck() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zFXCM = {};
	local zOanda = {};
	local zRequestReponse = nil;
	
	-- Get FXCM Positions
	zFXCM.OfferID = Host:findTable("offers"):find("Instrument", oInstrument).OfferID;
	zFXCM.Table = Host:findTable("trades"):findAll("OfferID", zFXCM.OfferID);
	zFXCM.Row = zFXCM.Table:next();
	zFXCM.Units = 0;
	while zFXCM.Row ~= nil do
		if zFXCM.Row.OfferID == zFXCM.OfferID then
			if zFXCM.Row.BS == "B" then
				zFXCM.Units = zFXCM.Units + zFXCM.Row.Lot
			elseif zFXCM.Row.BS == "S" then
				zFXCM.Units = zFXCM.Units + (zFXCM.Row.Lot * -1)
			else
				WriteToLog:error("PositionCheck() Failed | In Else Clause; zFXCM.Row.BS Format Is Invalid");
			end
		end
		zFXCM.Row = zFXCM.Table:next();
	end
	
	-- Get Oanda Positions
	zOanda.AttemptNumber = 1;
	while zOanda.AttemptNumber <= Oanda.MaxPostionCheckAttempts do
		zURL = CreateURLSyntax("Positions", "GET_OpenPositions", Oanda.Subdomain, Oanda.AccountID, nil, nil, FormatInstrument(oInstrument));
		zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
		zOanda.Units = nil;
		zOanda.LongUnits = nil;
		zOanda.ShortUnits = nil;
		if tonumber(ParseResponse("GET_OpenPositions", DecodeResponse(zRequestReponse)).Long.Units) ~= nil then 
			zOanda.LongUnits = tonumber(ParseResponse("GET_OpenPositions", DecodeResponse(zRequestReponse)).Long.Units)
		else
			zOanda.LongUnits = 0;
		end
		if tonumber(ParseResponse("GET_OpenPositions", DecodeResponse(zRequestReponse)).Short.Units) ~= nil then 
			zOanda.ShortUnits = tonumber(ParseResponse("GET_OpenPositions", DecodeResponse(zRequestReponse)).Short.Units)
		else
			zOanda.ShortUnits = 0;
		end
		zOanda.Units = zOanda.LongUnits + zOanda.ShortUnits;
		zOanda.AttemptNumber = zOanda.AttemptNumber + 1;
	end
	
	-- Review to ensure FXCM units and Oanda units match
	if zOanda.Units ~= nil and zFXCM.Units == zOanda.Units then
		WriteToLog:debug("PositionCheck() Finished | FXCM Units: " ..  zFXCM.Units .. " Oanda Units: " .. zOanda.Units .. ")");
		SendNotification("Trace", oInstrument, 0, "PositionCheck() Successful | Strategy OK", core.now());
	else
		WriteToLog:error("PositionCheck() Failed | FXCM Units: " ..  zFXCM.Units .. " Oanda Units: " .. zOanda.Units .. ")");
		SendNotification("All", oInstrument, 0, "PositionCheck() Failed | Strategy Stopped", core.now());
		StopStrategy = true;
	end
	WriteToLog:info("PositionCheck() <<<<< FINISHED <<<<< FINISHED <<<<<");
end


--------------------------------------------------------------------------------------------
-- Find Trade Function
--------------------------------------------------------------------------------------------

function FindTrade(oMessage, oMessage1, oMessage2)
	WriteToLog:info("FindTrade() >>>>> STARTING >>>>> STARTING >>>>>");
	local zTrade = {};
	local zPass = nil;
	
	zPass = true;

	-- http://www.fxcodebase.com/bin/products/IndicoreSDK/3.1.0/help/Lua/TTTrades.html
	if Host:findTable("trades"):find("OpenOrderID", oMessage1) ~= nil then
		zTrade.Row = Host:findTable("trades"):find("OpenOrderID", oMessage1);
		WriteToLog:debug("FindTrade() Finished | Ticket: " .. oMessage .. "; Order: " .. oMessage1 .. "; Direction: " .. zTrade.Row.BS .. "; Symbol: " .. zTrade.Row.Instrument .. "; Units: " .. zTrade.Row.Lot);
		CreateOrder(zTrade.Row.Instrument, zTrade.Row.Lot, zTrade.Row.BS);
	-- http://www.fxcodebase.com/bin/products/IndicoreSDK/3.1.0/help/Lua/TTClosedTrades.html
	elseif Host:findTable("closed trades"):find("CloseOrderID", oMessage1) ~= nil then
		zTrade.Row = Host:findTable("closed trades"):find("CloseOrderID", oMessage1);
		WriteToLog:debug("FindTrade() Finished | Ticket: " .. oMessage .. "; Order: " .. oMessage1 .. "; Direction: " .. zTrade.Row.BS .. "; Symbol: " .. zTrade.Row.Instrument .. "; Units: " .. zTrade.Row.Lot);
		CreateOrder(zTrade.Row.Instrument, zTrade.Row.Lot, FlipDirection(zTrade.Row.BS));
	else
		zPass = false;
	end
	
	if zPass then
		WriteToLog:debug("FindTrade() Finished | Called CreateOrder()");
		WriteToLog:info("FindTrade() <<<<< FINISHED <<<<< FINISHED <<<<<");
		SendNotification("Trace", zTrade.Row.Instrument, 0, "FindTrade() Successful | Strategy OK", core.now());
	else
		WriteToLog:error("FindTrade() failed via else clause; OrderID is not found in trades or closed trades tables");
		SendNotification("All", zTrade.Row.Instrument, 0, "FindTrade() Failed | Strategy Stopped", core.now());
		StopStrategy = true;
	end
end


--------------------------------------------------------------------------------------------
-- Create Order Function
--------------------------------------------------------------------------------------------

function CreateOrder(oInstrument, oSize, oDirection)
	WriteToLog:info("CreateOrder() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zOrder = {};
	local zURL = nil;
	local zOrderSyntax = nil;
	local zRequestReponse = nil;
	local zPass = nil;
	
	-- Default Values
	zOrder.TimeInForce = "FOK"
	zOrder.OrderType = "MARKET"
	zOrder.PositionFill = "REDUCE_FIRST"
	zOrder.AttemptNumber = 1;
	zPass = false;
	
	while zOrder.AttemptNumber <= Oanda.MaxOrderAttempts and zPass == false do
		zOrder.PriceBound = CreatePriceBounds(oInstrument, oDirection, Oanda.AllowedSlippageInPips);
		zURL = CreateURLSyntax("Orders", "POST_Order", Oanda.Subdomain, Oanda.AccountID, nil, nil, oInstrument);
		zOrderSyntax = CreateOrderSyntax(FormatDirection(oDirection, oSize), FormatInstrument(oInstrument), zOrder.TimeInForce , zOrder.PriceBound, zOrder.OrderType, zOrder.PositionFill);
		zRequestReponse = SendRequest("POST", zURL, zOrderSyntax, Oanda.APIToken);
		if string.match(zRequestReponse, "orderCreateTransaction") ~= nil and string.match(zRequestReponse, "orderFillTransaction") ~= nil then
			WriteToLog:error("CreateOrder() Successful | Attempt Number: " .. zOrder.AttemptNumber);
			zPass = true;
		else
			WriteToLog:error("CreateOrder() Failed | Attempt Number: " .. zOrder.AttemptNumber);
			SendNotification("Trace", oInstrument, 0, "CreateOrder() Failed | Attempt Number: " .. zOrder.AttemptNumber, core.now());
			zPass = false;
		end
		zOrder.AttemptNumber = zOrder.AttemptNumber + 1;
	end
	
	if zPass then
		WriteToLog:debug("CreateOrder() Finished | " .. zRequestReponse);
		WriteToLog:info("CreateOrder() <<<<< FINISHED <<<<< FINISHED <<<<<");
		SendNotification("Trace", oInstrument, 0, "CreateOrder() Successful | Strategy OK", core.now());
	else
		WriteToLog:error("CreateOrder() Failed");
		SendNotification("All", oInstrument, 0, "CreateOrder() Failed | Strategy Stopped", core.now());
		StopStrategy = true;
	end
	
	Timer.PositionCheckNew = Host:execute("setTimer", 201, 5);
end


--------------------------------------------------------------------------------------------
-- Create Price Bounds Function
--------------------------------------------------------------------------------------------

function CreatePriceBounds(oInstrument, oDirection, oPointsRange)
	WriteToLog:info("CreatePriceBounds() >>>>> STARTING >>>>> STARTING >>>>>");

	local zPrice = {};
	local zURL = nil;
	local zRequestReponse = nil;
	
	zURL = CreateURLSyntax("Account", "GET_Instruments", Oanda.Subdomain, Oanda.AccountID, nil, nil, FormatInstrument(oInstrument));
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	
	zPrice.PipLocation = tonumber(ParseResponse("GET_Instruments", DecodeResponse(zRequestReponse)).Instruments.PipLocation);
	zPrice.DisplayPrecision = ParseResponse("GET_Instruments", DecodeResponse(zRequestReponse)).Instruments.DisplayPrecision;
	zPrice.AllowedSlippageInDecimals = oPointsRange * FormatPips(zPrice.PipLocation)
	WriteToLog:debug("CreatePriceBounds() | Pip location: " .. zPrice.PipLocation);
	WriteToLog:debug("CreatePriceBounds() | Display precision: " .. zPrice.DisplayPrecision);
	WriteToLog:debug("CreatePriceBounds() | Allowed slippage in decimal form: " .. zPrice.AllowedSlippageInDecimals);
	
	zURL = CreateURLSyntax("Pricing", "GET_Pricing", Oanda.Subdomain, Oanda.AccountID, nil, nil, oInstrument);
	zRequestReponse = SendRequest("GET", zURL, nil, Oanda.APIToken);
	if oDirection == "B" then
		zPrice.BestAskPrice = ParseResponse("GET_Pricing", DecodeResponse(zRequestReponse)).Asks.Best.Price;
		zPrice.PriceBound = FormatPrecision(zPrice.BestAskPrice + zPrice.AllowedSlippageInDecimals, zPrice.DisplayPrecision);
		WriteToLog:debug("CreatePriceBounds() | Best ask price: " .. zPrice.BestAskPrice);
	elseif oDirection == "S" then
		zPrice.BestBidPrice = ParseResponse("GET_Pricing", DecodeResponse(zRequestReponse)).Bids.Best.Price;
		zPrice.PriceBound = FormatPrecision(zPrice.BestBidPrice - zPrice.AllowedSlippageInDecimals, zPrice.DisplayPrecision);
		WriteToLog:debug("CreatePriceBounds() | Best bid price: " .. zPrice.BestBidPrice);
	else
		WriteToLog:error("CreatePriceBounds() Failed | In Else Clause");
	end
	
	WriteToLog:debug("CreatePriceBounds() Finished | " .. zPrice.PriceBound);
	WriteToLog:info("CreatePriceBounds() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zPriceBound;
end


--------------------------------------------------------------------------------------------
-- Create URL Function
--------------------------------------------------------------------------------------------

function CreateURLSyntax(oEndpoint, oEndpointType, oSubdomain, oAccountID, oOrderID, oTradeID, oInstrument)
	WriteToLog:info("CreateURLSyntax() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zCompleteURL = nil;
	local zBaseURL = nil;
	local zBaseURL = "https://" .. oSubdomain .. "/v3/accounts/" .. oAccountID
	
	-- Acount Endpoints
	-- http://developer.oanda.com/rest-live-v20/account-ep/
	if oEndpoint == "Account" then
		if oEndpointType == "GET_Accounts" then zCompleteURL = "https://" .. oSubdomain .. "/v3/accounts";
		elseif oEndpointType == "GET_Account" then zCompleteURL = zBaseURL;
		elseif oEndpointType == "GET_Summary" then zCompleteURL = zBaseURL .. "/summary";
		elseif oEndpointType == "GET_Instruments" then zCompleteURL = zBaseURL .. "/instruments?instruments=" .. FormatInstrument(oInstrument);
		elseif oEndpointType == "PATCH_Configuration" then zCompleteURL = zBaseURL .. "/configuration";
		elseif oEndpointType == "GET_Changes" then zCompleteURL = zBaseURL .. "/changes";
		WriteToLog:error("CreateURLSyntax() Failed | In Sub Else Clause");
		end
	-- Orders Endpoints
	-- http://developer.oanda.com/rest-live-v20/orders-ep/
	elseif oEndpoint == "Orders" then
		if oEndpointType == "POST_Order" then zCompleteURL = zBaseURL .. "/orders";
		elseif oEndpointType == "GET_Orders" then zCompleteURL = zBaseURL .. "/orders";
		elseif oEndpointType == "GET_PendingOrders" then zCompleteURL = zBaseURL .. "/pendingOrders";
		elseif oEndpointType == "GET_SingleOrder" then zCompleteURL = zBaseURL .. "/orders/" .. oOrderID;
		elseif oEndpointType == "PUT_ReplaceOrder" then zCompleteURL = zBaseURL .. "/orders/" .. oOrderID;
		elseif oEndpointType == "PUT_CancelOrder" then zCompleteURL = zBaseURL .. "/orders" .. oOrderID .. "/cancel";
		elseif oEndpointType == "PUT_UpdateExtension" then zCompleteURL = zBaseURL .. "/orders" .. oOrderID .."/clientExtensions";
		WriteToLog:error("CreateURLSyntax() Failed | In Sub Else Clause");
		end
	-- Trades Endpoints
	-- http://developer.oanda.com/rest-live-v20/trades-ep/
	elseif oEndpoint == "Trades" then
		if oEndpointType == "GET_Trades" then zCompleteURL = zBaseURL .. "/trades";
		elseif oEndpointType == "GET_OpenTrade" then zCompleteURL = zBaseURL .. "/openTrades";
		elseif oEndpointType == "GET_SingleTrade" then zCompleteURL = zBaseURL .. "/trades/" .. oTradeID;
		elseif oEndpointType == "PUT_CloseTrade" then zCompleteURL = zBaseURL .. "/trades/" .. oTradeID .. "/close";
		elseif oEndpointType == "PUT_UpdateExtension" then zCompleteURL = zBaseURL .. "/trades/" .. oTradeID .. "/clientExtensions";
		elseif oEndpointType == "PUT_ModifyLinkedOrder" then zCompleteURL = zBaseURL .. "/trades/" .. oTradeID .. "/orders";
		WriteToLog:error("CreateURLSyntax() Failed | In Sub Else Clause");
		end
	-- Positions Endpoints
	-- http://developer.oanda.com/rest-live-v20/positions-ep/
	elseif oEndpoint == "Positions" then
		if oEndpointType == "GET_Postions" then zCompleteURL = zBaseURL .. "/positions";
		elseif oEndpointType == "GET_OpenPositions" then zCompleteURL = zBaseURL .. "/openPositions";
		elseif oEndpointType == "GET_InstrumentPosition" then zCompleteURL = zBaseURL .. "/positions/" ..  oInstrument;
		elseif oEndpointType == "PUT_ClosePosition" then zCompleteURL = zBaseURL .. "/positions/" ..  oInstrument .. "/close";
		WriteToLog:error("CreateURLSyntax() Failed | In Sub Else Clause");
		end
	-- Pricing Endpoints
	-- http://developer.oanda.com/rest-live-v20/pricing-ep/
	elseif oEndpoint == "Pricing" then
		if oEndpointType == "GET_Pricing" then zCompleteURL = zBaseURL .. "/pricing?instruments=" .. FormatInstrument(oInstrument);
		elseif oEndpointType == "GET_PricingStream" then zCompleteURL = zBaseURL .. "/pricing/stream";
		WriteToLog:error("CreateURLSyntax() Failed | In Sub Else Clause");
		end
	else
		WriteToLog:error("CreateURLSyntax() Failed | In Else Clause");
	end
	
	WriteToLog:debug("CreateURLSyntax() Finished | " .. zCompleteURL);
	WriteToLog:info("CreateURLSyntax() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zCompleteURL;
end 


--------------------------------------------------------------------------------------------
-- Create Order Syntax Function
--------------------------------------------------------------------------------------------

function CreateOrderSyntax(oUnits, oInstrument, oTimeInForce, oPriceBound, oOrderType, oPositionFill)
	WriteToLog:info("CreateOrderSyntax() >>>>> STARTING >>>>> STARTING >>>>>");

	local zOrderTable = {};
	zOrderTable["order"] = nil;
	local zJSONString = nil;

	zOrderTable["order"] = {units=oUnits, instrument=oInstrument, timeInForce=oTimeInForce, priceBound=oPriceBound, type=oOrderType, positionFill=oPositionFill};
	zJSONString = EncodeResponse(zOrderTable);

	WriteToLog:debug("CreateOrderSyntax() Finished | " .. tostring(zJSONString));
	WriteToLog:info("CreateOrderSyntax() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zJSONString;
end


--------------------------------------------------------------------------------------------
-- Send Request Function
--------------------------------------------------------------------------------------------

function SendRequest(oHTTPType, oCompleteURL, oOrderSyntax, oAPIToken)
	WriteToLog:info("SendRequest() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zRequest = {};
	zRequest.URL = nil;
	zRequest.HeadersAuthorization = nil;
	zRequest.HeadersContentType = "application/json";
	zRequest.Content = nil;
	zRequest.Object = nil;
	zRequest.Response = nil;
	
	-- Create HTTP Object
	zRequest.Object = http_lua.createRequest();
	
	-- Set Up Variables
	zRequest.URL = oCompleteURL;
	zRequest.HeadersAuthorization = "Bearer " .. oAPIToken;
	zRequest.Object:setRequestHeader("Authorization", zRequest.HeadersAuthorization);
	
	-- Send HTTP Object
	if oHTTPType == "GET" then
		zRequest.Object:start(zRequest.URL, "GET");
	elseif oHTTPType == "POST" then
		zRequest.Object:setRequestHeader("Content-Type", zRequest.HeadersContentType);
		zRequest.Content = oOrderSyntax;
		zRequest.Object:start(zRequest.URL, "POST", zRequest.Content);
	elseif oHTTPType == "PUT" then
		WriteToLog:error("SendRequest() Failed | In Else Clause | Attempted With PUT HTTP Type");
	elseif oHTTPType == "PATCH" then
		WriteToLog:error("SendRequest() Failed | In Else Clause | Attempted With PATCH HTTP Type");
	else
		WriteToLog:error("SendRequest() Failed | In Else Clause");
	end
	
	-- Pause For Response; Up To 10 seconds
	Timer.SendRequest = Host:execute("setTimer", 400, 10);
	while zRequest.Object:loading() do
	end
	Host:execute("killTimer", Timer.SendRequest);
	
	-- Error Catching Routine
	if not(zRequest.Object:success()) then
		WriteToLog:error("SendRequest() Failed | HTTP Status " .. zRequest.Object:httpStatus());
	end
	if zRequest.Object:httpStatus() ~= 200 and zRequest.Object:httpStatus() ~= 201 then
		WriteToLog:info("SendRequest() Returned | HTTP Status " .. zRequest.Object:httpStatus());
	end

	-- Process Response
	zRequest.Response = zRequest.Object:response();
	
	WriteToLog:debug("SendRequest() Finished | " .. zRequest.Response);
	WriteToLog:info("SendRequest() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zRequest.Response;
end 


--------------------------------------------------------------------------------------------
-- Encode Response Function
--------------------------------------------------------------------------------------------

function EncodeResponse(oRequest)
	WriteToLog:info("EncodeResponse() >>>>> STARTING >>>>> STARTING >>>>>");
	
	JSON = assert(loadfile "JSON.lua")();
	local zLUATable = {};

	zLUATable = JSON:encode(oRequest);
	
	WriteToLog:debug("EncodeResponse() Finished | " .. tostring(zLUATable));
	WriteToLog:info("EncodeResponse() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zLUATable;
end


--------------------------------------------------------------------------------------------
-- Decode Response Function
--------------------------------------------------------------------------------------------

function DecodeResponse(oResponse)
	WriteToLog:info("DecodeResponse() >>>>> STARTING >>>>> STARTING >>>>>");
	
	JSON = assert(loadfile "JSON.lua")();
	local zLUATable = {};

	zLUATable = JSON:decode(oResponse);

	WriteToLog:debug("DecodeResponse() Finished | " .. tostring(zLUATable));
	WriteToLog:info("DecodeResponse() <<<<< FINISHED <<<<< FINISHED <<<<<");
	return zLUATable;
end


--------------------------------------------------------------------------------------------
-- Parse Response Function
--------------------------------------------------------------------------------------------

function ParseResponse(oType, oResponse)
	WriteToLog:info("ParseResponse() >>>>> STARTING >>>>> STARTING >>>>>");
	
	-- http://developer.oanda.com/rest-live-v20/account-ep/
	if oType == "GET_Accounts" then
		local Accounts = {};
		if pcall(function () Accounts.ID = tostring(oResponse["accounts"][1]["id"]); end) then 
			Accounts.ID = tostring(oResponse["accounts"][1]["id"]);
		else Accounts.ID = tostring(nil); end
		if pcall(function () Accounts.Tags = tostring(oResponse["accounts"][1]["tags"][1]); end) then 
			Accounts.Tags = tostring(oResponse["accounts"][1]["tags"][1]);
		else Accounts.Tags = tostring(nil); end

		WriteToLog:debug("ParseResponse() | Accounts.ID: " .. Accounts.ID);
		WriteToLog:debug("ParseResponse() | Accounts.Tags: " .. Accounts.Tags);
		
		return Accounts;
	-- http://developer.oanda.com/rest-live-v20/account-ep/
	elseif oType == "GET_Account" then
		local Account = {};
		
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		
		return Accounts;
	-- http://developer.oanda.com/rest-live-v20/instrument-ep/
	elseif oType == "GET_Instruments" then
		local Account = {};
		Account.Instruments = {};
		if pcall(function () Account.Instruments.DisplayName = tostring(oResponse["instruments"][1]["displayName"]); end) then 
			Account.Instruments.DisplayName = tostring(oResponse["instruments"][1]["displayName"]);
		else Account.Instruments.DisplayName = tostring(nil); end
		if pcall(function () Account.Instruments.DisplayPrecision = tostring(oResponse["instruments"][1]["displayPrecision"]); end) then 
			Account.Instruments.DisplayPrecision = tostring(oResponse["instruments"][1]["displayPrecision"]);
		else Account.Instruments.DisplayPrecision = tostring(nil); end
		if pcall(function () Account.Instruments.MarginRate = tostring(oResponse["instruments"][1]["marginRate"]); end) then 
			Account.Instruments.MarginRate = tostring(oResponse["instruments"][1]["marginRate"]);
		else Account.Instruments.MarginRate = tostring(nil); end
		if pcall(function () Account.Instruments.MaximumOrderUnits = tostring(oResponse["instruments"][1]["maximumOrderUnits"]); end) then 
			Account.Instruments.MaximumOrderUnits = tostring(oResponse["instruments"][1]["maximumOrderUnits"]);
		else Account.Instruments.MaximumOrderUnits = tostring(nil); end
		if pcall(function () Account.Instruments.MaximumPositionSize = tostring(oResponse["instruments"][1]["maximumPositionSize"]); end) then 
			Account.Instruments.MaximumPositionSize = tostring(oResponse["instruments"][1]["maximumPositionSize"]);
		else Account.Instruments.MaximumPositionSize = tostring(nil); end
		if pcall(function () Account.Instruments.MaximumTrailingStopDistance = tostring(oResponse["instruments"][1]["maximumTrailingStopDistance"]); end) then 
			Account.Instruments.MaximumTrailingStopDistance = tostring(oResponse["instruments"][1]["maximumTrailingStopDistance"]);
		else Account.Instruments.MaximumTrailingStopDistance = tostring(nil); end
		if pcall(function () Account.Instruments.MinimumTradeSize = tostring(oResponse["instruments"][1]["minimumTradeSize"]); end) then 
			Account.Instruments.MinimumTradeSize = tostring(oResponse["instruments"][1]["minimumTradeSize"]);
		else Account.Instruments.MinimumTradeSize = tostring(nil); end
		if pcall(function () Account.Instruments.MinimumTrailingStopDistance = tostring(oResponse["instruments"][1]["minimumTrailingStopDistance"]); end) then 
			Account.Instruments.MinimumTrailingStopDistance = tostring(oResponse["instruments"][1]["minimumTrailingStopDistance"]);
		else Account.Instruments.MinimumTrailingStopDistance = tostring(nil); end
		if pcall(function () Account.Instruments.Name = tostring(oResponse["instruments"][1]["name"]); end) then 
			Account.Instruments.Name = tostring(oResponse["instruments"][1]["name"]);
		else Account.Instruments.Name = tostring(nil); end
		if pcall(function () Account.Instruments.PipLocation = tostring(oResponse["instruments"][1]["pipLocation"]); end) then 
			Account.Instruments.PipLocation = tostring(oResponse["instruments"][1]["pipLocation"]);
		else Account.Instruments.PipLocation = tostring(nil); end
		if pcall(function () Account.Instruments.TradeUnitsPrecision = tostring(oResponse["instruments"][1]["tradeUnitsPrecision"]); end) then 
			Account.Instruments.TradeUnitsPrecision = tostring(oResponse["instruments"][1]["tradeUnitsPrecision"]);
		else Account.Instruments.TradeUnitsPrecision = tostring(nil); end
		if pcall(function () Account.Instruments.Type = tostring(oResponse["instruments"][1]["type"]); end) then 
			Account.Instruments.Type = tostring(oResponse["instruments"][1]["type"]);
		else Account.Instruments.Type = tostring(nil); end

		WriteToLog:debug("ParseResponse() | Account.Instruments.DisplayName: " .. Account.Instruments.DisplayName);
		WriteToLog:debug("ParseResponse() | Account.Instruments.DisplayPrecision: " .. Account.Instruments.DisplayPrecision);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MarginRate: " .. Account.Instruments.MarginRate);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MaximumOrderUnits: " .. Account.Instruments.MaximumOrderUnits);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MaximumPositionSize: " .. Account.Instruments.MaximumPositionSize);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MaximumTrailingStopDistance: " .. Account.Instruments.MaximumTrailingStopDistance);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MinimumTradeSize: " .. Account.Instruments.MinimumTradeSize);
		WriteToLog:debug("ParseResponse() | Account.Instruments.MinimumTrailingStopDistance: " .. Account.Instruments.MinimumTrailingStopDistance);
		WriteToLog:debug("ParseResponse() | Account.Instruments.Name: " .. Account.Instruments.Name);
		WriteToLog:debug("ParseResponse() | Account.Instruments.PipLocation: " .. Account.Instruments.PipLocation);
		WriteToLog:debug("ParseResponse() | Account.Instruments.TradeUnitsPrecision: " .. Account.Instruments.TradeUnitsPrecision);
		WriteToLog:debug("ParseResponse() | Account.Instruments.Type: " .. Account.Instruments.Type);

		return Account;
	-- http://developer.oanda.com/rest-live-v20/positions-ep/
	elseif oType == "GET_OpenPositions" then
		local Positions = {};
		if pcall(function () Positions.Instrument = tostring(oResponse["positions"][1]["instrument"]); end) then 
			Positions.Instrument = tostring(oResponse["positions"][1]["instrument"]);
		else Positions.Instrument = tostring(nil); end
		if pcall(function () Positions.PL = tostring(oResponse["positions"][1]["pl"]); end) then 
			Positions.PL = tostring(oResponse["positions"][1]["pl"]);
		else Positions.PL = tostring(nil); end
		if pcall(function () Positions.ResettablePL = tostring(oResponse["positions"][1]["resettablePL"]); end) then 
			Positions.ResettablePL = tostring(oResponse["positions"][1]["resettablePL"]);
		else Positions.ResettablePL = tostring(nil); end
		if pcall(function () Positions.UnrealizedPL = tostring(oResponse["positions"][1]["unrealizedPL"]); end) then 
			Positions.UnrealizedPL = tostring(oResponse["positions"][1]["unrealizedPL"]);
		else Positions.UnrealizedPL = tostring(nil); end
		if pcall(function () Positions.LastTransactionID = tostring(oResponse["lastTransactionID"]); end) then 
			Positions.LastTransactionID = tostring(oResponse["lastTransactionID"]);
		else Positions.LastTransactionID = tostring(nil); end

		WriteToLog:debug("ParseResponse() | Positions.Instrument: " .. Positions.Instrument);
		WriteToLog:debug("ParseResponse() | Positions.PL: " .. Positions.PL);
		WriteToLog:debug("ParseResponse() | Positions.ResettablePL: " .. Positions.ResettablePL);
		WriteToLog:debug("ParseResponse() | Positions.UnrealizedPL: " .. Positions.UnrealizedPL);
		WriteToLog:debug("ParseResponse() | Positions.LastTransactionID: " .. Positions.LastTransactionID);
		
		Positions.Long = {};
		if pcall(function () Positions.Long.TradeIDs = tostring(oResponse["positions"][1]["long"]["tradeIDs"][1]); end) then 
			Positions.Long.TradeIDs = tostring(oResponse["positions"][1]["long"]["tradeIDs"][1]);
		else Positions.Long.TradeIDs = tostring(nil); end
		if pcall(function () Positions.Long.AveragePrice = tostring(oResponse["positions"][1]["long"]["averagePrice"]); end) then 
			Positions.Long.AveragePrice = tostring(oResponse["positions"][1]["long"]["averagePrice"]);
		else Positions.Long.AveragePrice = tostring(nil); end
		if pcall(function () Positions.Long.UnrealizedPL = tostring(oResponse["positions"][1]["long"]["unrealizedPL"]); end) then 
			Positions.Long.UnrealizedPL = tostring(oResponse["positions"][1]["long"]["unrealizedPL"]);
		else Positions.Long.UnrealizedPL = tostring(nil); end
		if pcall(function () Positions.Long.PL = tostring(oResponse["positions"][1]["long"]["pl"]); end) then
			Positions.Long.PL = tostring(oResponse["positions"][1]["long"]["pl"]);
		else Positions.Long.PL = tostring(nil); end
		if pcall(function () Positions.Long.ResettablePL = tostring(oResponse["positions"][1]["long"]["resettablePL"]); end) then 
			Positions.Long.ResettablePL = tostring(oResponse["positions"][1]["long"]["resettablePL"]);
		else Positions.Long.ResettablePL = tostring(nil); end
		if pcall(function () Positions.Long.Units = tostring(oResponse["positions"][1]["long"]["units"]); end) then 
			Positions.Long.Units = tostring(oResponse["positions"][1]["long"]["units"]);
		else Positions.Long.Units = tostring(nil); end

		WriteToLog:debug("ParseResponse() | Positions.Long.TradeIDs: " .. Positions.Long.TradeIDs);
		WriteToLog:debug("ParseResponse() | Positions.Long.AveragePrice: " .. Positions.Long.AveragePrice);
		WriteToLog:debug("ParseResponse() | Positions.Long.UnrealizedPL: " .. Positions.Long.UnrealizedPL);
		WriteToLog:debug("ParseResponse() | Positions.Long.PL: " .. Positions.Long.PL);
		WriteToLog:debug("ParseResponse() | Positions.Long.ResettablePL: " .. Positions.Long.ResettablePL);
		WriteToLog:debug("ParseResponse() | Positions.Long.Units: " .. Positions.Long.Units);
		
		Positions.Short = {};
		if pcall(function () Positions.Short.TradeIDs = tostring(oResponse["positions"][1]["short"]["tradeIDs"][1]); end) then 
			Positions.Short.TradeIDs = tostring(oResponse["positions"][1]["short"]["tradeIDs"][1]);
		else Positions.Short.TradeIDs = tostring(nil); end
		if pcall(function () Positions.Short.AveragePrice = tostring(oResponse["positions"][1]["short"]["averagePrice"]); end) then 
			Positions.Short.AveragePrice = tostring(oResponse["positions"][1]["short"]["averagePrice"]);
		else Positions.Short.AveragePrice = tostring(nil); end
		if pcall(function () Positions.Short.UnrealizedPL = tostring(oResponse["positions"][1]["short"]["unrealizedPL"]); end) then 
			Positions.Short.UnrealizedPL = tostring(oResponse["positions"][1]["short"]["unrealizedPL"]);
		else Positions.Short.UnrealizedPL = tostring(nil); end
		if pcall(function () Positions.Short.PL = tostring(oResponse["positions"][1]["short"]["pl"]); end) then
			Positions.Short.PL = tostring(oResponse["positions"][1]["short"]["pl"]);
		else Positions.Short.PL = tostring(nil); end
		if pcall(function () Positions.Short.ResettablePL = tostring(oResponse["positions"][1]["short"]["resettablePL"]); end) then 
			Positions.Short.ResettablePL = tostring(oResponse["positions"][1]["short"]["resettablePL"]);
		else Positions.Short.ResettablePL = tostring(nil); end
		if pcall(function () Positions.Short.Units = tostring(oResponse["positions"][1]["short"]["units"]); end) then 
			Positions.Short.Units = tostring(oResponse["positions"][1]["short"]["units"]);
		else Positions.Short.Units = tostring(nil); end

		WriteToLog:debug("ParseResponse() | Positions.Short.TradeIDs: " .. Positions.Short.TradeIDs);
		WriteToLog:debug("ParseResponse() | Positions.Short.AveragePrice: " .. Positions.Short.AveragePrice);
		WriteToLog:debug("ParseResponse() | Positions.Short.UnrealizedPL: " .. Positions.Short.UnrealizedPL);
		WriteToLog:debug("ParseResponse() | Positions.Short.PL: " .. Positions.Short.PL);
		WriteToLog:debug("ParseResponse() | Positions.Short.ResettablePL: " .. Positions.Short.ResettablePL);
		WriteToLog:debug("ParseResponse() | Positions.Short.Units: " .. Positions.Short.Units);
		
		return Positions;
	-- http://developer.oanda.com/rest-live-v20/orders-ep/
	elseif oType == "POST_Orders" then
		local Orders = {};
	
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		-- ADD SUPPORT FOR THIS RESPONSE TYPE
		
		return Orders;
	-- http://developer.oanda.com/rest-live-v20/pricing-ep/
	elseif oType == "GET_Pricing" then
		local Prices = {};
		if pcall(function () Prices.Type = tostring(oResponse["prices"][1]["type"]); end) then 
			Prices.Type = tostring(oResponse["prices"][1]["type"]);
		else Prices.Type = tostring(nil); end
		if pcall(function () Prices.Time = tostring(oResponse["prices"][1]["time"]); end) then 
			Prices.Time = tostring(oResponse["prices"][1]["time"]);
		else Prices.Time = tostring(nil); end
		if pcall(function () Prices.CloseoutBid = tostring(oResponse["prices"][1]["closeoutBid"]); end) then 
			Prices.CloseoutBid = tostring(oResponse["prices"][1]["closeoutBid"]);
		else Prices.CloseoutBid = tostring(nil); end
		if pcall(function () Prices.CloseoutAsk = tostring(oResponse["prices"][1]["closeoutAsk"]); end) then 
			Prices.CloseoutAsk = tostring(oResponse["prices"][1]["closeoutAsk"]);
		else Prices.CloseoutAsk = tostring(nil); end
		if pcall(function () Prices.Status = tostring(oResponse["prices"][1]["status"]); end) then 
			Prices.Status = tostring(oResponse["prices"][1]["status"]);
		else Prices.Status = tostring(nil); end
		if pcall(function () Prices.Tradeable = tostring(oResponse["prices"][1]["tradeable"]); end) then 
			Prices.Tradeable = tostring(oResponse["prices"][1]["tradeable"]);
		else Prices.Tradeable = tostring(nil); end
		if pcall(function () Prices.Instrument = tostring(oResponse["prices"][1]["instrument"]); end) then 
			Prices.Instrument = tostring(oResponse["prices"][1]["instrument"]);
		else Prices.Instrument = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.Type: " .. Prices.Type);
		WriteToLog:debug("ParseResponse() | Prices.Time: " .. Prices.Time);
		WriteToLog:debug("ParseResponse() | Prices.CloseoutBid: " .. Prices.CloseoutBid);
		WriteToLog:debug("ParseResponse() | Prices.CloseoutAsk: " .. Prices.CloseoutAsk);
		WriteToLog:debug("ParseResponse() | Prices.Status: " .. Prices.Status);
		WriteToLog:debug("ParseResponse() | Prices.Tradeable: " .. Prices.Tradeable);
		WriteToLog:debug("ParseResponse() | Prices.Instrument: " .. Prices.Instrument);
		
		Prices.UnitsAvailable = {};
		Prices.UnitsAvailable.Default = {};
		if pcall(function () Prices.UnitsAvailable.Default.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["default"]["long"]); end) then 
			Prices.UnitsAvailable.Default.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["default"]["long"]);
		else Prices.UnitsAvailable.Default.Long = tostring(nil); end
		if pcall(function () Prices.UnitsAvailable.Default.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["default"]["short"]); end) then 
			Prices.UnitsAvailable.Default.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["default"]["short"]);
		else Prices.UnitsAvailable.Default.Short = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.Default.Long: " .. Prices.UnitsAvailable.Default.Long);
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.Default.Short: " .. Prices.UnitsAvailable.Default.Short);
		
		Prices.UnitsAvailable.OpenOnly = {};
		if pcall(function () Prices.UnitsAvailable.OpenOnly.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["openOnly"]["long"]); end) then 
			Prices.UnitsAvailable.OpenOnly.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["openOnly"]["long"]);
		else Prices.UnitsAvailable.OpenOnly.Long = tostring(nil); end
		if pcall(function () Prices.UnitsAvailable.OpenOnly.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["openOnly"]["short"]); end) then 
			Prices.UnitsAvailable.OpenOnly.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["openOnly"]["short"]);
		else Prices.UnitsAvailable.OpenOnly.Short = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.OpenOnly.Long: " .. Prices.UnitsAvailable.OpenOnly.Long);
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.OpenOnly.Short: " .. Prices.UnitsAvailable.OpenOnly.Short);
		
		Prices.UnitsAvailable.ReduceFirst = {};
		if pcall(function () Prices.UnitsAvailable.ReduceFirst.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceFirst"]["long"]); end) then 
			Prices.UnitsAvailable.ReduceFirst.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceFirst"]["long"]);
		else Prices.UnitsAvailable.ReduceFirst.Long = tostring(nil); end
		if pcall(function () Prices.UnitsAvailable.ReduceFirst.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceFirst"]["short"]); end) then 
			Prices.UnitsAvailable.ReduceFirst.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceFirst"]["short"]);
		else Prices.UnitsAvailable.ReduceFirst.Short = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.ReduceFirst.Long: " .. Prices.UnitsAvailable.ReduceFirst.Long);
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.ReduceFirst.Short: " .. Prices.UnitsAvailable.ReduceFirst.Short);
		
		Prices.UnitsAvailable.ReduceOnly = {};
		if pcall(function () Prices.UnitsAvailable.ReduceOnly.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceOnly"]["long"]); end) then 
			Prices.UnitsAvailable.ReduceOnly.Long = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceOnly"]["long"]);
		else Prices.UnitsAvailable.ReduceOnly.Long = tostring(nil); end
		if pcall(function () Prices.UnitsAvailable.ReduceOnly.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceOnly"]["short"]); end) then 
			Prices.UnitsAvailable.ReduceOnly.Short = tostring(oResponse["prices"][1]["unitsAvailable"]["reduceOnly"]["short"]);
		else Prices.UnitsAvailable.ReduceOnly.Short = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.ReduceOnly.Long: " .. Prices.UnitsAvailable.ReduceOnly.Long);
		WriteToLog:debug("ParseResponse() | Prices.UnitsAvailable.ReduceOnly.Short: " .. Prices.UnitsAvailable.ReduceOnly.Short);
		
		Prices.QuoteHomeConversionFactors = {}
		if pcall(function () Prices.QuoteHomeConversionFactors.PositiveUnits = tostring(oResponse["prices"][1]["quoteHomeConversionFactors"]["positiveUnits"]); end) then 
			Prices.QuoteHomeConversionFactors.PositiveUnits = tostring(oResponse["prices"][1]["quoteHomeConversionFactors"]["positiveUnits"]);
		else Prices.QuoteHomeConversionFactors.PositiveUnits = tostring(nil); end
				if pcall(function () Prices.QuoteHomeConversionFactors.NegativeUnits = tostring(oResponse["prices"][1]["quoteHomeConversionFactors"]["negativeUnits"]); end) then 
			Prices.QuoteHomeConversionFactors.NegativeUnits = tostring(oResponse["prices"][1]["quoteHomeConversionFactors"]["negativeUnits"]);
		else Prices.QuoteHomeConversionFactors.NegativeUnits = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.QuoteHomeConversionFactors.PositiveUnits: " .. Prices.QuoteHomeConversionFactors.PositiveUnits);
		WriteToLog:debug("ParseResponse() | Prices.QuoteHomeConversionFactors.NegativeUnits: " .. Prices.QuoteHomeConversionFactors.NegativeUnits);
		
		Prices.Bids = {};
		Prices.Bids.Best = {};
		if pcall(function () Prices.Bids.Best.Price = tostring(oResponse["prices"][1]["bids"][1]["price"]); end) then 
			Prices.Bids.Best.Price = tostring(oResponse["prices"][1]["bids"][1]["price"]);
		else Prices.Bids.Best.Price = tostring(nil); end
			if pcall(function () Prices.Bids.Best.Liquidity = tostring(oResponse["prices"][1]["bids"][1]["liquidity"]); end) then 
			Prices.Bids.Best.Liquidity = tostring(oResponse["prices"][1]["bids"][1]["liquidity"]);
		else Prices.Bids.Best.Liquidity = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.Bids.Best.Price: " .. Prices.Bids.Best.Price);
		WriteToLog:debug("ParseResponse() | Prices.Bids.Best.Liquidity: " .. Prices.Bids.Best.Liquidity);
		
		Prices.Asks = {};
		Prices.Asks.Best = {};
		if pcall(function () Prices.Asks.Best.Price = tostring(oResponse["prices"][1]["asks"][1]["price"]); end) then 
			Prices.Asks.Best.Price = tostring(oResponse["prices"][1]["asks"][1]["price"]);
		else Prices.Asks.Best.Price = tostring(nil); end
			if pcall(function () Prices.Asks.Best.Liquidity = tostring(oResponse["prices"][1]["asks"][1]["liquidity"]); end) then 
			Prices.Asks.Best.Liquidity = tostring(oResponse["prices"][1]["asks"][1]["liquidity"]);
		else Prices.Asks.Best.Liquidity = tostring(nil); end
		
		WriteToLog:debug("ParseResponse() | Prices.Asks.Best.Price: " .. Prices.Asks.Best.Price);
		WriteToLog:debug("ParseResponse() | Prices.Asks.Best.Liquidity: " .. Prices.Asks.Best.Liquidity);
		
		return Prices;
	else
		WriteToLog:error("ParseResponse() Failed | In Else Clause");
	end
	
	WriteToLog:debug("ParseResponse() Finished | Table Returned");
	WriteToLog:info("ParseResponse() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
end


--------------------------------------------------------------------------------------------
-- Formatting Functions
--------------------------------------------------------------------------------------------

function SendNotification(oType, oSymbol, oOpen, oMessage, oTime)
	WriteToLog:info("SendNotification() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zTimeInTable = {};
	local zDate = nil;
	local zTime = nil; 
	
	zTimeInTable = core.dateToTable(core.now());
	zDate = string.format("%02i/%02i/%02i", zTimeInTable.month, zTimeInTable.day, zTimeInTable.year);
	zTime = string.format("%02i:%02i", zTimeInTable.hour, zTimeInTable.min);	
	
	if oType == "Terminal" then
		terminal:alertMessage(oSymbol, oOpen, oMessage, oTime)
	elseif oType == "Trace" then
		Host:trace(oMessage);
	elseif oType == "StartEmail" then
		if FXCM.SendEmail then
			terminal:alertEmail(FXCM.EmailAddress, "Strategy Successfully Started on " .. zDate .. " at " .. zTime, oMessage);
		end
	elseif oType == "All" then
		terminal:alertMessage(oSymbol, oOpen, oMessage, oTime)
		Host:trace(oMessage);
		if FXCM.SendEmail then
			terminal:alertEmail(FXCM.EmailAddress, "Review ".. oSymbol .. "; Issue on " .. zDate .. " at " .. zTime, oMessage);
		end
	else
		WriteToLog:error("SendNotification() Failed | In Else Clause");
	end
	
	WriteToLog:info("SendNotification() >>>>> STARTING >>>>> STARTING >>>>>");
end


function FlipDirection(oDirection)
	WriteToLog:info("FlipDirection() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zDirection = nil;
	if oDirection == "B" then
		zDirection = "S";
	elseif oDirection == "S" then
		zDirection = "B";
	else	
		WriteToLog:error("FlipDirection() Failed | In Else Clause");
	end
	
	WriteToLog:debug("FlipDirection() Finished with " .. zDirection);
	WriteToLog:info("FlipDirection() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
	return zDirection;
end


function FormatDirection(oDirection, oSize)
	WriteToLog:info("FormatDirection() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zSize = nil;
	if oDirection == "B" then
		zSize = oSize;
	elseif oDirection == "S" then
		zSize = oSize * -1;
	else	
		WriteToLog:error("FormatDirection() Failed | In Else Clause");
	end
	
	WriteToLog:debug("FormatDirection() Finished | " .. zSize);
	WriteToLog:info("FormatDirection() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
	return zSize;
end


function FormatInstrument(oInstrument)
	WriteToLog:info("FormatInstrument() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zInstrument = nil;
	if string.match(oInstrument, "/") ~= nil then
		zInstrument = string.gsub(oInstrument, "/", "_");
	elseif string.match(oInstrument, "_") ~= nil then
		zInstrument = oInstrument;
	else
		WriteToLog:error("FormatInstrument() Failed | In Else Clause");
	end
	
	WriteToLog:debug("FormatInstrument() Finished | " .. zInstrument);
	WriteToLog:info("FormatInstrument() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
	return zInstrument;
end


function FormatPips(oPipLocation)
	WriteToLog:info("FormatPips() >>>>> STARTING >>>>> STARTING >>>>>");

	local zMultiplier = nil;
	if oPipLocation == 0 then
		zMultiplier = 1;
	elseif oPipLocation == -1 then
		zMultiplier = .1;
	elseif oPipLocation == -2 then
		zMultiplier = .01;
	elseif oPipLocation == -3 then
		zMultiplier = .001;
	elseif oPipLocation == -4 then
		zMultiplier = .0001;
	elseif oPipLocation == -5 then
		zMultiplier = .00001;
	else
		WriteToLog:error("FormatPips() Failed | In Else Clause");
	end

	WriteToLog:debug("FormatPips() Finished | " .. zMultiplier);
	WriteToLog:info("FormatPips() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
	return zMultiplier;
end


function FormatPrecision(oInput, oDecimals)
	WriteToLog:info("FormatPrecision() >>>>> STARTING >>>>> STARTING >>>>>");
	
	local zOutput = nil;
	zOutput = string.format("%." .. oDecimals .. "f", oInput);

	WriteToLog:debug("FormatPips() Finished | " .. zOutput);
	WriteToLog:info("FormatPips() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
	return zOutput;
end


--------------------------------------------------------------------------------------------
-- Async Operations Function
--------------------------------------------------------------------------------------------

function AsyncOperationFinished(oReference, oSuccess, oMessage, oMessage1, oMessage2)
	-- http://www.fxcodebase.com/bin/products/IndicoreSDK/3.1.0/help/Lua/host.execute_subscribeTradeEvents.html
	WriteToLog:info("AsyncOperationFinished() >>>>> STARTING >>>>> STARTING >>>>>"); 
	
	if oReference == 100 then
		if not StopStrategy then
			Host:execute("killTimer", Timer.HealthCheck);
			HealthCheck("GBP/JPY");
			PositionCheck("GBP/JPY");
			WriteToLog:debug("AsyncOperationFinished() Finished | Ran HealthCheck(), Ran PositionCheck(), Killed Timer.HealthCheck");
		else
			Host:execute("killTimer", Timer.HealthCheck);
		end
	elseif oReference == 200 then
		if not StopStrategy then
			PositionCheck("GBP/JPY");
			WriteToLog:debug("AsyncOperationFinished() Finished | Ran PositionCheck()");
		end
	elseif oReference == 201 then
		if not StopStrategy then
			Host:execute("killTimer", Timer.PositionCheckNew);
			PositionCheck("GBP/JPY");
			WriteToLog:debug("AsyncOperationFinished() Finished | Ran PositionCheck(), Killed Timer.PositionCheckNew");
		end
	elseif oReference == 300 then
		if not StopStrategy then
			FindTrade(oMessage, oMessage1, oMessage2);
			WriteToLog:debug("AsyncOperationFinished Finished | Ran FindTrade()");
		end
	elseif oReference == 400 then
		if not StopStrategy then
			Host:execute("killTimer", Timer.SendRequest);
			WriteToLog:debug("AsyncOperationFinished() Finished | Killed Timer.SendRequest");
		else
			Host:execute("killTimer", Timer.SendRequest);
		end
	else
		WriteToLog:error("AsyncOperationFinished() Failed | In Else Clause");
	end
	
	WriteToLog:info("AsyncOperationFinished() <<<<< FINISHED <<<<< FINISHED <<<<<"); 
end


--------------------------------------------------------------------------------------------
-- Log Functions
--------------------------------------------------------------------------------------------

Logger = {["OFF"]=0, ["ERROR"]=1, ["INFO"]=2, ["DEBUG"]=3};
Logger.__index = Logger;

function GetLogPath()
	local zDirectory
	local zFileName
	local zFileHandle
	local zOSCommand

	zDirectory = os.getenv("USERPROFILE");
	if zDirectory ~= nil then
		if string.find(zDirectory, "Users") ~= nil then
			zDirectory = zDirectory .. "\\Desktop\\Marketscope\\Logs";
		else
			zDirectory = zDirectory .. "\\Marketscope\\Logs"
		end
		zFileName = string.format("%s\\install.txt", zDirectory);
		zFileHandle = io.open(zFileName, "w");
		if zFileHandle == nil then
			zOSCommand = string.format("MKDIR %s", zDirectory);
			os.execute(zOSCommand);
			zFileHandle = io.open(zFileName, "w");
		end
		if zFileHandle ~= nil then
			zFileHandle:close();
		end
	end
	return zDirectory;
end


function Logger:create(zFileName, zLogLevel)
	assert(zFileName ~= nil, "Invalid Log File Name");
	assert(zLogLevel ~= nil, "Invalid Log Level");
	assert(type(zLogLevel) == "number", "Invalid Log Level");
	assert(zLogLevel == Logger.OFF or zLogLevel == Logger.INFO or zLogLevel == Logger.DEBUG or zLogLevel == Logger.ERROR, "Invalid log level");
	local logger = {_logPath = GetLogPath() .. "\\" .. zFileName .. ".txt", _logLevel = zLogLevel};
	
	setmetatable(logger, self);
	return logger;
end


function Logger:GetLogPath()
	return self._logPath;
end


function Logger:writeLog(olevel, oMessage)
	local zFile = io.open(self._logPath, "a+");
	if zFile ~= nil then
		zFile:write(os.date().." | ".. olevel .." | ".. oMessage .."\n");
		zFile:close();
	end
end


function Logger:info(oMessage)
	if self._logLevel >= Logger.INFO then self:writeLog(" INFO", oMessage); end
end


function Logger:error(oMessage)
	if self._logLevel >= Logger.ERROR then self:writeLog("ERROR", oMessage); end
end


function Logger:debug(oMessage)
	if self._logLevel >= Logger.DEBUG then self:writeLog("DEBUG", oMessage); end
end