------------------------------------------Overview------------------------------------------
-- Name:             Hue Lights Control
-- Notes:            Copyright (c) 2015 Jeremy Gulickson
-- Version:          1.0.03092015
-- Usage:            
--
-- Requirements:     FXTS (FXCM Trading Station)
-- Download Link:    http://download.fxcorporate.com/FXCM/FXTS2Install.EXE
-- Documentation:    http://www.fxcodebase.com/documents/IndicoreSDK-2.3/web-content.html
-- Documentation:    http://www.developers.meethue.com/philips-hue-api
--
---------------------------------------Version History--------------------------------------
-- v1.0.03092015:    Initial release; proof of concept. 
--
--------------------------------------------------------------------------------------------

require("http_lua");

local Source;
local Host;
local BridgeAddress;
local UserName;
local TradesTable;
local ClosedTradesTable;
local Request = {};


function Init()
    strategy:name("Hue Lights Control");
    strategy:type(core.Both);
	
	strategy.parameters:addGroup("Hue Bridge");

    strategy.parameters:addString("BridgeAddress", "Bridge Address", "Enter the bridge IP address.", "");
	strategy.parameters:addString("UserName", "User Name", "Enter the user name.", "");

	strategy.parameters:addGroup("Display Options");
    strategy.parameters:addString("AccountName", "Account Number", "Select the account to monitor.", "");
	strategy.parameters:setFlag("AccountName", core.FLAG_ACCOUNT);
end


function Prepare()
	Source = instance.source;
    Host = core.host;
	
	BridgeAddress = instance.parameters.BridgeAddress;
	UserName = instance.parameters.UserName;

	TradesTable = Host:findTable("trades");
	ClosedTradesTable = Host:findTable("closed trades");
	
	instance:name("Hue Lights Control (Account:" .. instance.parameters.AccountName .. ")");
	
	Host:execute("subscribeTradeEvents", 1, "trades");
end


function Update()
	-- Not Used
end


function CheckLightState(OrderID)
	-- http://www.fxcodebase.com/documents/IndicoreSDK-2.3/ext_kit_http.html
	
	Request.URL = "http://" .. BridgeAddress .. "/api/" .. UserName .. "/lights/1"
	Request.Object = http_lua.createRequest();
	Request.Object:start(Request.URL, "GET");
	Host:trace("GET URL = " .. Request.URL);
	Request.LoadingTimerSet = Host:execute("setTimer", 2, 10);
	
	while Request.Object:loading() do
	end
	Host:execute("killTimer", Request.LoadingTimerSet);
	
	if not(Request.Object:success()) then
		Host:trace("CheckLightState Failed");
	end

	if Request.Object:httpStatus() ~= 200 then
		Host:trace("Hue Bridge Not Available" .. Request.Object:httpStatus());
	end
	
	Request.Response = Request.Object:response();
	Request.Pattern = "\"on\":true,\"";
	
	if string.match(Request.Response, Request.Pattern) ~= nil then
		Host:trace("Lights are on");
		FindPosition(OrderID)
	else
		Host:trace("Lights are off");
	end
end


function FindPosition(OrderID)
	local PositionOpened, PositionProfitable = nil;
	
	if TradesTable:find("OpenOrderID", OrderID) ~= nil then
		Host:trace("Trade Opened; TradeID = " .. OrderID);
		PositionOpened = true;
		CreateHueSettings(PositionOpened, PositionProfitable)
	elseif ClosedTradesTable:find("CloseOrderID", OrderID) ~= nil then
		Host:trace("Trade Closed; TradeID = " .. OrderID);
		PositionOpened = false;
		GetTradePL(OrderID, PositionOpened);
	else
		Host:trace("TradeID is not found in trades or closed trades tables");
	end
end


function GetTradePL(OrderID, PositionOpened)
	local PositionPL, PositionProfitable = nil;
	
	if PositionOpened == true then
		PositionPL = TradesTable:find("OpenOrderID", OrderID).PL
		Host:trace("Trade Opened; PL = " .. PositionPL);
	else
		PositionPL = ClosedTradesTable:find("CloseOrderID", OrderID).PL
		Host:trace("Trade Closed; PL = " .. PositionPL);
	end
	
	if PositionPL >= 0 then
		PositionProfitable  = true
		Host:trace("Trade Profitable");
	else
		PositionProfitable  = false
		Host:trace("Trade Unprofitable");
	end
	
	CreateHueSettings(PositionOpened, PositionProfitable)
end


function CreateHueSettings(PositionOpened, PositionProfitable)
	local HueSettings = nil;

	if PositionOpened == true then
		HueSettings = "{\"bri\": 255,\"xy\": [0.2853,0.2653],\"alert\":\"none\",\"transitiontime\": 30}";
		Host:trace("Hue Setting = " .. HueSettings);
	elseif PositionProfitable == true then
		HueSettings = "{\"bri\": 255,\"xy\": [0.4417,0.4600],\"alert\":\"none\",\"transitiontime\": 30}";
		Host:trace("Hue Setting = " .. HueSettings);
	else
		HueSettings = "{\"bri\": 255,\"xy\": [0.5923,0.3433],\"alert\":\"none\",\"transitiontime\": 30}";
		Host:trace("Hue Setting = " .. HueSettings);
	end

	Request.Repeat = true;
	SetLightState(HueSettings)
end


function SetLightState(HueSettings)
	-- http://www.fxcodebase.com/documents/IndicoreSDK-2.3/ext_kit_http.html
	
	Request.URL = "http://" .. BridgeAddress .. "/api/" .. UserName .. "/groups/0/action"
	Request.Object = http_lua.createRequest();
	Request.Object:start(Request.URL, "PUT", HueSettings);
	Host:trace("PUT URL = " .. Request.URL);
	Request.LoadingTimerCheck = Host:execute("setTimer", 3, 10);
	
	while Request.Object:loading() do
	end
	Host:execute("killTimer", Request.LoadingTimerCheck);
	
	if not(Request.Object:success()) then
		Host:trace("SetLightState Failed");
	end

	if Request.Object:httpStatus() ~= 200 then
		Host:trace("Hue Bridge Not Available" .. Request.Object:httpStatus());
	end

	if Request.Repeat == true then
		Request.Repeat = false;
		Request.FlashTimer = Host:execute("setTimer", 4, 4);
		Request.ReturnTimer = Host:execute("setTimer", 5, 5);
	end
end


function AsyncOperationFinished(Reference, Success, TradeID, OrderID, OrderReqID)
	-- http://www.fxcodebase.com/documents/IndicoreSDK-2.3/signal_AsyncOperationFinished.html
	
	if Reference == 1 then
		CheckLightState(OrderID);
	elseif Reference == 2 then
		Request.Object:cancel();
		Host:execute("killTimer", Request.LoadingTimerCheck);
		Host:trace("CheckLightState Timed Out");
	elseif Reference == 3 then
		Request.Object:cancel();
		Host:execute("killTimer", Request.LoadingTimerSet);
		Host:trace("SetLightState Timed Out");
	elseif Reference == 4 then
		success, error = pcall (function() Host:execute("killTimer", Request.FlashTimer) end);
		if success then
			SetLightState("{\"alert\":\"select\"}");
		end;
	elseif Reference == 5 then
		success, error = pcall (function() Host:execute("killTimer", Request.ReturnTimer) end);
		if success then
			SetLightState("{\"bri\": 2554\"xy\": [0.4248,0.4016],\"alert\":\"none\",\"transitiontime\": 30}");
		end;
	end
end