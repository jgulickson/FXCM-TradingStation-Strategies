---------------------------------------- Overview ------------------------------------------
-- Name:                    Investment Dashboard
-- Notes:                   Copyright (c) 2017 Jeremy Gulickson
-- Version:                 1.6.08312017
-- Format:                  major.minor.mmddyyyy
--
-- Description:             Proof of concept to calculate and aggregate select values from
--                          user specified FXCM, Oanda and/or Robinhood account(s). Currently
--                          includes equity, day p/l and leverage though modifying or adding
--                          additional data points is trivial. Oanda and Robinhood data is sourced
--                          via RESTful API queries.
--
-- Platform Requirements:   FXTS (FXCM Trading Station) -> http://download.fxcorporate.com/FXCM/FXTS2Install.EXE
--                          http_lua.dll                -> Included by default in FXTS
--                          JSON.lua                    -> http://regex.info/blog/lua/json
--
-- Login Requirements:      FXCM      -> Username + password
--                                       // Note this is entered in FXTS not in indicator options
--                          Oanda     -> Token
--                                       // Generated and retrieved from Oanda's online account portal
--                          Robinhood -> Username + password + 2FA code (optional)
--                                       // Token appears to only be valid for a session only and thus 
--                                       // the indicator will grab token at initialization
--
-- FXCM Documentation:      http://www.fxcodebase.com/bin/products/IndicoreSDK/3.1.0/help/Lua/web-content.html
-- Oanda Documentation:     http://developer.oanda.com/rest-live-v20/introduction/
-- Robinhood Documentation: https://github.com/sanko/Robinhood
--
-- Know Limitations:        -> Does not support 2FA for Oanda accounts
--                          -> 2FA support for Robhinhood accounts is clunky
--                          -> Oanda account must be type v20
--                          -> Robinhood API is undocumented and therefore unannounced changes
--                             may break funtionality
--                          -> Minimal error handling for incorrect username or password values
--                          -> Minimal error handling for api endpoint conductivity
--
-------------------------------------- Version History -------------------------------------
-- v1.0.03272017:           Feature Release
--                          -> Initial release; proof of concept
--
-- v1.1.04052017:           Cosmetic Release
--                          -> Added color formatting for values
--                          -> Update x & y coordinates calculation
--
-- v1.2.04102017:           Cosmetic Release
--                          -> Added side variable to control presentation
--
-- v1.3.04202017:           Cosmetic Release
--                          -> Made Github ready
--                          -> Removed email functionality
--
-- v1.4.08032017:           Feature Release
--                          -> Updated Robinhood data to include extended hours values
--                          -> Added Robinhood support for 2 factor authentication
--
-- v1.5.08072017            Bug Fix Release
--                          -> Improved Robinhood 2 factor authentication experience
--                          -> Addressed issues with Robinhood extended hours values not populating from server
--
-- v1.6.08312017            Bug Fix Release
--                          -> Addressed issues with Robinhood leverage values
--
--------------------------------------------------------------------------------------------


--------------------------------------------------------------------------------------------
-- Global Variable Setup
--------------------------------------------------------------------------------------------
-- Routine Notes:           Global variables are initialized as arrays *solely* for
--                          readability purposes.       
--
--------------------------------------------------------------------------------------------

-- Require LUA extension to support HTTPS protocol
require("http_lua");

-- Global Oanda variables
local Oanda = {};
Oanda.Demo_URL = "api-fxpractice.oanda.com";
Oanda.Real_URL = "api-fxtrade.oanda.com";
Oanda.URL = nil;
Oanda.Account_ID = nil;
Oanda.Account_Type = nil;
Oanda.API_Token = nil;

-- Global Robinhood variables
local Robinhood = {};
Robinhood.TFA_Mode = nil;
Robinhood.TFA_Type = nil;
Robinhood.TFA_Code = nil;
Robinhood.URL = "api.robinhood.com"
Robinhood.Portfolio_URL = nil;
Robinhood.Account_ID = nil;
Robinhood.Password = nil;
Robinhood.API_Token = nil;

-- Global FXCM variables
local FXCM = {};
FXCM.Account_ID = nil;

-- Global timer variables
local Timer = {};
Timer.Initialized = nil;
Timer.Send_Request = nil;
Timer.Update_Frequency = nil;

-- Global font variables
local Font = {};
Font.Equity = nil;
Font.Floating_PL = nil;
Font.Day_PL = nil;
Font.Leverage = nil;

-- Global format variables
local Format = {};
Format.Equity = nil;
Format.Leverage = nil;
Format.Neutral = nil;
Format.Positive = nil;
Format.Negative = nil;
Format.Side = nil;
Format.Digits = 0;

--------------------------------------------------------------------------------------------
-- Initialize Function
--------------------------------------------------------------------------------------------

function Init()
 	indicator:name("Investment Dashboard");
    indicator:description("Investment Dashboard")
    indicator:type(core.Indicator);
	
	indicator.parameters:addGroup("General");
	indicator.parameters:addInteger("Update_Frequency", "Update Frequency", "Enter time between updates in minutes.", 10, 1, 60);
	
	indicator.parameters:addGroup("Format");
	indicator.parameters:addColor("Format_Equity", "Equity Value", "Select the color of equity vales.", core.rgb(255, 255, 255));
	indicator.parameters:addColor("Format_Leverage", "Leverage Value", "Select the color of leverage vales.", core.rgb(255, 255, 255));
	indicator.parameters:addColor("Format_Neutral", "Neutral Values", "Select the color of neutral values.", core.rgb(192, 192, 192));
	indicator.parameters:addColor("Format_Positive", "Positive Values", "Select the color of positive values.", core.rgb(128, 255, 0));
	indicator.parameters:addColor("Format_Negative", "Negative Values", "Select the color of negative values.", core.rgb(255, 53, 53));
	indicator.parameters:addString("Format_Side", "Side", "Select which side to display values.", "Right")
	indicator.parameters:addStringAlternative("Format_Side", "Right", "", "Right");
	indicator.parameters:addStringAlternative("Format_Side", "Left", "", "Left");
	
	indicator.parameters:addGroup("Robinhood");
	indicator.parameters:addString("Robinhood_Account_ID", "Account ID", "Enter the account id to monitor.", "");
	indicator.parameters:addString("Robinhood_Password", "Password", "Enter the password.", "");
	indicator.parameters:addBoolean("Robinhood_TFA_Mode", "2FA Mode", "Enable two factor authentication mode.", true);
	indicator.parameters:addString("Robinhood_TFA_Code", "2FA Code", "Enter the two factor authentication code.", "");
	
	indicator.parameters:addGroup("Oanda");
	indicator.parameters:addString("Oanda_Account_ID", "Account ID", "Enter the account id to monitor.", "");
	indicator.parameters:addString("Oanda_Account_Type", "Account Type", "Select the account type.", "Real")
	indicator.parameters:addStringAlternative("Oanda_Account_Type", "Demo", "", "Demo");
	indicator.parameters:addStringAlternative("Oanda_Account_Type", "Real", "", "Real");
	indicator.parameters:addString("Oanda_API_Token", "API Token", "Enter the API token.","");
	
	indicator.parameters:addGroup("FXCM");
	indicator.parameters:addString("FXCM_Account_ID", "Account ID", "Select the account id to monitor.", "");
	indicator.parameters:setFlag("FXCM_Account_ID", core.FLAG_ACCOUNT);
end


--------------------------------------------------------------------------------------------
-- Prepare Function
--------------------------------------------------------------------------------------------

function Prepare()
	instance:name("Investment Dashboard");
	
	Timer.Initialized = core.host:execute("setTimer", 100, 10);
	Timer.Update_Frequency = core.host:execute("setTimer", 200, instance.parameters.Update_Frequency * 60);

	Format.Equity = instance.parameters.Format_Equity;
	Format.Leverage = instance.parameters.Format_Leverage;
	Format.Neutral = instance.parameters.Format_Neutral;
	Format.Positive = instance.parameters.Format_Positive;
	Format.Negative = instance.parameters.Format_Negative;
	Format.Side = instance.parameters.Format_Side;
	
	Robinhood.Account_ID = instance.parameters.Robinhood_Account_ID;
	Robinhood.Password = instance.parameters.Robinhood_Password;
	Robinhood.TFA_Mode = instance.parameters.Robinhood_TFA_Mode;
	if Robinhood.TFA_Mode then Get_Robinhood_API_Token_TFA_Step_1(); end
	Robinhood.TFA_Code = instance.parameters.Robinhood_TFA_Code;
	
	Oanda.Account_ID = instance.parameters.Oanda_Account_ID;
	if instance.parameters.Oanda_Account_Type == "Real" then
		Oanda.URL = Oanda.Real_URL;
	elseif instance.parameters.Oanda_Account_Type == "Demo" then
		Oanda.URL = Oanda.Demo_URL;
	end
	Oanda.API_Token = instance.parameters.Oanda_API_Token;
	
	FXCM.Account_ID = instance.parameters.FXCM_Account_ID;

	Font.Equity = core.host:execute("createFont", "Verdana", 70, false, true);
	Font.Floating_PL = core.host:execute("createFont", "Verdana", 30, false, false);
	Font.Day_PL = core.host:execute("createFont", "Verdana", 30, false, false);
	Font.Leverage = core.host:execute("createFont", "Verdana", 30, false, false);
end


--------------------------------------------------------------------------------------------
-- Get Robinhood API Token
--------------------------------------------------------------------------------------------

function Get_Robinhood_API_Token()
	local zURL = Create_Robinhood_URL_Syntax("Authentication", "POST_Login", Robinhood.URL, nil, nil, nil, nil);
	local zAuthentication = {};
	zAuthentication.username = Robinhood.Account_ID;
	zAuthentication.password = Robinhood.Password;
	local zResponse = Send_Request("Robinhood", "POST", zURL, nil, nil , nil, Encode_Request(zAuthentication));
	Robinhood.API_Token = Parse_Robinhood_Response("Authentication", "POST_Login", Decode_Response(zResponse)).Token;
end


--------------------------------------------------------------------------------------------
-- Get Robinhood API Token Two Factor Authentication Step 1
--------------------------------------------------------------------------------------------

function Get_Robinhood_API_Token_TFA_Step_1()
	local zURL = Create_Robinhood_URL_Syntax("Authentication", "POST_Login", Robinhood.URL, nil, nil, nil, nil);
	local zAuthentication = {};
	zAuthentication.username = Robinhood.Account_ID;
	zAuthentication.password = Robinhood.Password;
	local zResponse = Send_Request("Robinhood", "POST", zURL, nil, nil , nil, Encode_Request(zAuthentication));
	Robinhood.TFA_Type = Parse_Robinhood_Response("Authentication", "POST_Login", Decode_Response(zResponse)).TFA_Type;
end


--------------------------------------------------------------------------------------------
-- Get Robinhood API Token Two Factor Authentication Step 2
--------------------------------------------------------------------------------------------

function Get_Robinhood_API_Token_TFA_Step_2()
	if Robinhood.TFA_Type == "sms" then
		local zURL = Create_Robinhood_URL_Syntax("Authentication", "POST_Login", Robinhood.URL, nil, nil, nil, nil);
		local zAuthentication = {};
		zAuthentication.username = Robinhood.Account_ID;
		zAuthentication.password = Robinhood.Password;
		zAuthentication.mfa_code = Robinhood.TFA_Code;
		local zResponse = Send_Request("Robinhood", "POST", zURL, nil, nil , nil, Encode_Request(zAuthentication));
		Robinhood.API_Token = Parse_Robinhood_Response("Authentication", "POST_Login", Decode_Response(zResponse)).Token;
	else
		Send_Notification("Alert", "", 0, "Get_Robinhood_API_Token_TFA_Step_2() Failed | In Else Clause", core.now(), "");
	end
end


--------------------------------------------------------------------------------------------
-- Get Robinhood Portfolio URL
--------------------------------------------------------------------------------------------

function Get_Robinhood_Portfolio_URL()
	local zURL = Create_Robinhood_URL_Syntax("Accounts", "GET_Accounts", Robinhood.URL, nil, nil, nil, nil);
	local zResponse = Send_Request("Robinhood", "GET", zURL, nil, nil , Robinhood.API_Token, nil);
	Robinhood.Portfolio_URL = Parse_Robinhood_Response("Accounts", "GET_Accounts", Decode_Response(zResponse)).Portfolio_URL;
end


--------------------------------------------------------------------------------------------
-- Update Function
--------------------------------------------------------------------------------------------

function Update()
	-- Not employed
end


--------------------------------------------------------------------------------------------
-- Update Values Function
--------------------------------------------------------------------------------------------

function Update_Display(aType, aEquity, aDay_PL, aFloating_PL, aLeverage)
	if Format.Side == "Left" then
		Update_Display_Format_Left(aType, aEquity, aDay_PL, aFloating_PL, aLeverage)
	elseif  Format.Side == "Right" then
		Update_Display_Format_Right(aType, aEquity, aDay_PL, aFloating_PL, aLeverage)
	end
end


--------------------------------------------------------------------------------------------
-- Update Values Function - Left Alignment
--------------------------------------------------------------------------------------------
-- Routine Notes:           This code is inefficient but works! Variable "Format.Digits"
--                          *may* be incorrect on first run but subsequent attempts will
--                          be accurate; impact is temporarily misaligned equity values.
--
--------------------------------------------------------------------------------------------

function Update_Display_Format_Left(aType, aEquity, aDay_PL, aFloating_PL, aLeverage)
	local Display = {};
	Display.yRobinhood_Equity_Offset = 46;
	Display.yRobinhood_Day_PL_Offset = Display.yRobinhood_Equity_Offset - 19;
	Display.yRobinhood_Floating_PL_Offset = Display.yRobinhood_Equity_Offset - 19;
	Display.yRobinhood_Leverage_Offset = Display.yRobinhood_Equity_Offset + 21;
	
	Display.yOanda_Equity_Offset = Display.yRobinhood_Equity_Offset * 3;
	Display.yOanda_Day_PL_Offset = Display.yOanda_Equity_Offset - 19;
	Display.yOanda_Floating_PL_Offset = Display.yOanda_Equity_Offset - 19;
	Display.yOanda_Leverage_Offset = Display.yOanda_Equity_Offset + 21;

	Display.xEquity_Offset = 5;
	Display.xDay_PL_Offset = nil;
	Display.xLeverage_Offset = nil;
	
	Format.Day_PL = Format_Color(aDay_PL);
	Format.Floating_PL = Format_Color(aFloating_PL);
	
	if aEquity ~= nil then		
		aEquity = Format_Financial(aEquity, 0);
	else aEquity = "0"; end
	if aFloating_PL ~= nil then		
		aFloating_PL = Format_Financial(aFloating_PL, 0);
	else aFloating_PL = "0"; end
	if aDay_PL ~= nil then		
		aDay_PL = Format_Financial(aDay_PL, 0);
	else aDay_PL = "0"; end
	if aLeverage ~= nil then		
		aLeverage = Format_Leverage(aLeverage, 2);
	else aLeverage = "0"; end

	if string.len(aEquity) == 6 then
		Display.Equity_Digits = string.len(aEquity) + 1;
		Display.xEquity_Offset = 65;
	else
		Display.Equity_Digits = string.len(aEquity);
	end	
	
	Display.xDay_PL_Offset = 58 * Display.Equity_Digits;
	Display.xFloating_PL_Offset = Display.xDay_PL_Offset;
	Display.xLeverage_Offset = Display.xDay_PL_Offset;
	
	if aType == "Robinhood" then
		core.host:execute("drawLabel1", 1, Display.xEquity_Offset, core.CR_LEFT, Display.yRobinhood_Equity_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Equity, Format.Equity, aEquity);
		core.host:execute("drawLabel1", 2, Display.xDay_PL_Offset, core.CR_LEFT, Display.yRobinhood_Day_PL_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Day_PL, Format.Day_PL, aDay_PL);
		core.host:execute("drawLabel1", 3, Display.xLeverage_Offset, core.CR_LEFT, Display.yRobinhood_Leverage_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Leverage, Format.Leverage, aLeverage);
	elseif aType == "Oanda" then
		core.host:execute("drawLabel1", 4, Display.xEquity_Offset, core.CR_LEFT, Display.yOanda_Equity_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Equity, Format.Equity, aEquity);
		core.host:execute("drawLabel1", 5, Display.xLeverage_Offset, core.CR_LEFT, Display.yOanda_Leverage_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Leverage, Format.Leverage, aLeverage);
	elseif aType == "FXCM" then
		core.host:execute("drawLabel1", 6, Display.xFloating_PL_Offset, core.CR_LEFT, Display.yOanda_Day_PL_Offset, core.CR_TOP, core.H_Right, core.V_Center, Font.Floating_PL, Format.Day_PL, aDay_PL);
	end
end


--------------------------------------------------------------------------------------------
-- Update Values Function - Right Alignment
--------------------------------------------------------------------------------------------
-- Routine Notes:           This code is inefficient but works! Variable "Format.Digits"
--                          *may* be incorrect on first run but subsequent attempts will
--                          be accurate; impact is temporarily misaligned equity values.
--
--------------------------------------------------------------------------------------------

function Update_Display_Format_Right(aType, aEquity, aDay_PL, aFloating_PL, aLeverage)
	Format.Day_PL = Format_Color(aDay_PL);
	Format.Floating_PL = Format_Color(aFloating_PL);
	
	if aFloating_PL ~= nil then		
		aFloating_PL = Format_Financial(aFloating_PL, 0);
	else aFloating_PL = "0"; end
	if aDay_PL ~= nil then		
		aDay_PL = Format_Financial(aDay_PL, 0);
	else aDay_PL = "0"; end
	if aLeverage ~= nil then		
		aLeverage = Format_Leverage(aLeverage, 2);
	else aLeverage = "0"; end
	if aEquity ~= nil then		
		aEquity = Format_Financial(aEquity, 0);
	else aEquity = "0"; end

	local Display = {};
	Display.Day_PL_Digits = string.len(aFloating_PL);
	Display.Floating_PL_Digits = string.len(aDay_PL);
	Display.Leverage_Digits = string.len(aLeverage);
		
	if Display.Leverage_Digits > Display.Day_PL_Digits then
		if Display.Leverage_Digits > Display.Floating_PL_Digits then
			Display.Digits = Display.Leverage_Digits;
		else
			Display.Digits = Display.Floating_PL_Digits;
		end
	elseif Display.Day_PL_Digits > Display.Floating_PL_Digits then
		Display.Digits = Display.Day_PL_Digits;
	else
		Display.Digits = Display.Floating_PL_Digits;
	end
	if Display.Digits > Format.Digits then Format.Digits = Display.Digits end;

	Display.xDay_PL_Offset = -5;
	Display.xFloating_PL_Offset = Display.xDay_PL_Offset;
	Display.xLeverage_Offset = Display.xDay_PL_Offset;
	Display.xEquity_Offset = -24 * Format.Digits;
	
	Display.yRobinhood_Equity_Offset = 46;
	Display.yRobinhood_Day_PL_Offset = Display.yRobinhood_Equity_Offset - 19;
	Display.yRobinhood_Floating_PL_Offset = Display.yRobinhood_Equity_Offset - 19;
	Display.yRobinhood_Leverage_Offset = Display.yRobinhood_Equity_Offset + 21;
	
	Display.yOanda_Equity_Offset = Display.yRobinhood_Equity_Offset * 3;
	Display.yOanda_Day_PL_Offset = Display.yOanda_Equity_Offset - 19;
	Display.yOanda_Floating_PL_Offset = Display.yOanda_Equity_Offset - 19;
	Display.yOanda_Leverage_Offset = Display.yOanda_Equity_Offset + 21;

	if aType == "Robinhood" then
		core.host:execute("drawLabel1", 1, Display.xEquity_Offset, core.CR_RIGHT, Display.yRobinhood_Equity_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Equity, Format.Equity, aEquity);
		core.host:execute("drawLabel1", 2, Display.xDay_PL_Offset, core.CR_RIGHT, Display.yRobinhood_Day_PL_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Day_PL, Format.Day_PL, aDay_PL);
		core.host:execute("drawLabel1", 3, Display.xLeverage_Offset, core.CR_RIGHT, Display.yRobinhood_Leverage_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Leverage, Format.Leverage, aLeverage);
	elseif aType == "Oanda" then
		core.host:execute("drawLabel1", 4, Display.xEquity_Offset, core.CR_RIGHT, Display.yOanda_Equity_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Equity, Format.Equity, aEquity);
		core.host:execute("drawLabel1", 5, Display.xLeverage_Offset, core.CR_RIGHT, Display.yOanda_Leverage_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Leverage, Format.Leverage, aLeverage);
	elseif aType == "FXCM" then
		core.host:execute("drawLabel1", 6, Display.xFloating_PL_Offset, core.CR_RIGHT, Display.yOanda_Day_PL_Offset, core.CR_TOP, core.H_Left, core.V_Center, Font.Floating_PL, Format.Day_PL, aDay_PL);
	end
end


--------------------------------------------------------------------------------------------
-- Get Robinhood Account Data
--------------------------------------------------------------------------------------------

function Get_Robinhood_Account_Data()
	local zURL = Create_Robinhood_URL_Syntax("Portfolio", "GET_Portfolio", Robinhood.URL, nil, nil, nil, nil);
	local zResponse = Send_Request("Robinhood", "GET", zURL, nil, nil , Robinhood.API_Token, nil);
	
	local zEquity = Parse_Robinhood_Response("Portfolio", "GET_Portfolio", Decode_Response(zResponse)).Equity;
	local zStart_Equity = Parse_Robinhood_Response("Portfolio", "GET_Portfolio", Decode_Response(zResponse)).Start_Equity;
	local zSize_In_USD = Parse_Robinhood_Response("Portfolio", "GET_Portfolio", Decode_Response(zResponse)).Size_In_USD;
	
	local zDay_PL
	local zLeverage = nil;
	if pcall(function () zDay_PL = zEquity - zStart_Equity; end) then
		zDay_PL = zEquity - zStart_Equity;
		if zEquity ~= nil and zSize_In_USD ~= nil then
			zLeverage = zSize_In_USD / zEquity;
		else
			zLeverage = "0";
		end
	else
		zDay_PL = nil;
		zEquity  = nil;
		zStart_Equity  = nil;
	end
		
	Update_Display("Robinhood", zEquity, zDay_PL, nil, zLeverage);
end


--------------------------------------------------------------------------------------------
-- Get Oanda Account Data
--------------------------------------------------------------------------------------------

function Get_Oanda_Account_Data()
	local zURL = Create_Oanda_URL_Syntax("Account", "GET_Summary", Oanda.URL, Oanda.Account_ID, nil, nil, nil);
	local zReponse = Send_Request("Oanda", "GET", zURL, nil, nil, Oanda.API_Token, nil);
	
	local zEquity = Parse_Oanda_Response("Account", "GET_Summary", Decode_Response(zReponse)).NAV;
	local zFloating_PL = Parse_Oanda_Response("Account", "GET_Summary", Decode_Response(zReponse)).Unrealized_PL;
	local zSize_In_USD = Parse_Oanda_Response("Account", "GET_Summary", Decode_Response(zReponse)).Size_In_USD;

	local zLeverage = nil;
	if pcall(function () zLeverage = zSize_In_USD / zEquity; end) then
		zLeverage = zSize_In_USD / zEquity;
	end
	Update_Display("Oanda", zEquity, nil, zFloating_PL, zLeverage);
end
	

--------------------------------------------------------------------------------------------
-- Get FXCM Account Data
--------------------------------------------------------------------------------------------

function Get_FXCM_Account_Data()
    if core.host:execute("isTableFilled", "accounts") then
		local zRow = core.host:findTable("accounts"):find("AccountID", FXCM.Account_ID);
		Update_Display("FXCM", zRow.Equity, zRow.DayPL, zRow.GrossPL, nil);
	end
end


--------------------------------------------------------------------------------------------
-- Create Robinhood URL Function
--------------------------------------------------------------------------------------------

function Create_Robinhood_URL_Syntax(aEndpoint, aEndpoint_Type, aSubdomain, aAccount_ID, aOrder_ID, aTrade_ID, aInstrument)
	local zBase_URL = "https://" .. aSubdomain .. "/";
	local zComplete_URL = nil;
	
	if aEndpoint == "Authentication" then
		if aEndpoint_Type == "POST_Login" then zComplete_URL = zBase_URL .. "api-token-auth/";
		else Send_Notification("Alert", "", 0, "Create_Robinhood_URL_Syntax() Failed | In Sub Else Clause", core.now(), "");
		end
	elseif aEndpoint == "Accounts" then
		if aEndpoint_Type == "GET_Accounts" then zComplete_URL = zBase_URL .. "accounts/";
		else Send_Notification("Alert", "", 0, "Create_Robinhood_URL_Syntax() Failed | In Sub Else Clause", core.now(), "");
		end
	elseif aEndpoint == "Portfolio" then
		if aEndpoint_Type == "GET_Portfolio" then zComplete_URL = Robinhood.Portfolio_URL;
		else Send_Notification("Alert", "", 0, "Create_Robinhood_URL_Syntax() Failed | In Sub Else Clause", core.now(), "");
		end
	else
		Send_Notification("Alert", "", 0, "Create_Robinhood_URL_Syntax() Failed | In Else Clause", core.now(), "");
	end
	
	return zComplete_URL;
end


--------------------------------------------------------------------------------------------
-- Create Oanda URL Function
--------------------------------------------------------------------------------------------

function Create_Oanda_URL_Syntax(aEndpoint, aEndpoint_Type, aSubdomain, aAccount_ID, aOrder_ID, aTrade_ID, aInstrument)
	local zBase_URL = "https://" .. aSubdomain .. "/v3/accounts/" .. aAccount_ID;
	local zComplete_URL = nil;
	
	if aEndpoint == "Account" then
		if aEndpoint_Type == "GET_Accounts" then zComplete_URL = "https://" .. aSubdomain .. "/v3/accounts";
		elseif aEndpoint_Type == "GET_Account" then zComplete_URL = zBase_URL;
		elseif aEndpoint_Type == "GET_Summary" then zComplete_URL = zBase_URL .. "/summary";
		else Send_Notification("Alert", "", 0, "Create_Oanda_URL_Syntax() Failed | In Sub Else Clause", core.now(), "");
		end
	else
		Send_Notification("Alert", "", 0, "Create_Oanda_URL_Syntax() Failed | In Else Clause", core.now(), "");
	end
	
	return zComplete_URL;
end


--------------------------------------------------------------------------------------------
-- Send Request Function
--------------------------------------------------------------------------------------------

function Send_Request(aRequest_Type, aHTTP_Type, aComplete_URL, aAccount_ID, aPassword, aAPI_Token, zPost_Payload)
	local zObject = http_lua.createRequest();
	zObject:setRequestHeader("Content-Type", "application/json");
	
	if aHTTP_Type == "GET" then
		local zHeaders_Authorization = nil;
		if aRequest_Type == "Oanda" then
			zHeaders_Authorization = "Bearer " .. aAPI_Token;
		elseif aRequest_Type == "Robinhood" then		
			zHeaders_Authorization = "Token " .. aAPI_Token;
		else
			Send_Notification("Alert", "", 0, "Send_Request() Failed | In Else Sub Clause", core.now(), "");
		end
		zObject:setRequestHeader("Authorization", zHeaders_Authorization);
		zObject:start(aComplete_URL, "GET");
	elseif aHTTP_Type == "POST" then
		zObject:start(aComplete_URL, "POST", zPost_Payload);
	else
		Send_Notification("Alert", "", 0, "Send_Request() Failed | In Else Clause", core.now(), "");
	end

	Timer.Send_Request = core.host:execute("setTimer", 500, 10);
	while zObject:loading() do
	end
	core.host:execute("killTimer", Timer.Send_Request);
	
	if not(zObject:success()) then
		Send_Notification("Alert", "", 0, "Send_Request() Failed | HTTP Status " .. zObject:httpStatus(), core.now(), "");
	end
	if zObject:httpStatus() ~= 200 and zObject:httpStatus() ~= 201 then
		Send_Notification("Trace", "", 0, "Send_Request() Returned | HTTP Status " .. zObject:httpStatus(), core.now(), "");
	end
	
	return zObject:response();
end 


--------------------------------------------------------------------------------------------
-- Encode Response Function
--------------------------------------------------------------------------------------------

function Encode_Request(aRequest)
	JSON = assert(loadfile "JSON.lua")();
	aRequest = JSON:encode(aRequest);
	return aRequest;
end


--------------------------------------------------------------------------------------------
-- Decode Response Function
--------------------------------------------------------------------------------------------

function Decode_Response(aResponse)
	JSON = assert(loadfile "JSON.lua")();
	aResponse = JSON:decode(aResponse);
	return aResponse;
end


--------------------------------------------------------------------------------------------
-- Parse Robinhood Response Function
--------------------------------------------------------------------------------------------

function Parse_Robinhood_Response(oEndpoint, oEndpoint_Type, aResponse)
	if oEndpoint == "Authentication" then
		if oEndpoint_Type == "POST_Login" then
			local POST_Login = {};
			if pcall(function () POST_Login.Token = tostring(aResponse["token"]); end) then
				POST_Login.Token = tostring(aResponse["token"]);
			else POST_Login.Token = nil; end
			if pcall(function () POST_Login.TFA_Type = tostring(aResponse["mfa_type"]); end) then
				POST_Login.TFA_Type = tostring(aResponse["mfa_type"]);
			else POST_Login.TFA_Type = nil; end
			return POST_Login;
		else
			Send_Notification("Alert", "", 0, "Parse_Robinhood_Response() Failed | In Sub Else Clause", core.now(), "");
		end	
	elseif oEndpoint == "Accounts" then
		if oEndpoint_Type == "GET_Accounts" then
			local GET_Accounts = {};
			if pcall(function () GET_Accounts.Portfolio_URL = tostring(aResponse["results"][1]["portfolio"]); end) then
				GET_Accounts.Portfolio_URL = tostring(aResponse["results"][1]["portfolio"]);
			else GET_Accounts.Portfolio_URL = nil; end
			return GET_Accounts;
		else
			Send_Notification("Alert", "", 0, "Parse_Robinhood_Response() Failed | In Sub Else Clause", core.now(), "");
		end	
	elseif oEndpoint == "Portfolio" then
		if oEndpoint_Type == "GET_Portfolio" then
			local GET_Portfolio = {};
			if pcall(function () GET_Portfolio.Equity = tostring(aResponse["equity"]); end) then
				GET_Portfolio.Equity = tostring(aResponse["equity"]);
			else GET_Accounts.Equity = nil; end
			if pcall(function () GET_Portfolio.Extened_Hours_Equity = tostring(aResponse["extended_hours_equity"]); end) then
				GET_Portfolio.Extened_Hours_Equity = tostring(aResponse["extended_hours_equity"]);
			else GET_Accounts.Extened_Hours_Equity = nil; end
			if not string.match(GET_Portfolio.Extened_Hours_Equity, "%a") then
				GET_Portfolio.Equity = GET_Portfolio.Extened_Hours_Equity;
			end
			
			if pcall(function () GET_Portfolio.Start_Equity = tostring(aResponse["equity_previous_close"]); end) then
				GET_Portfolio.Start_Equity = tostring(aResponse["equity_previous_close"]);
			else GET_Portfolio.Start_Equity = nil; end

			if pcall(function () GET_Portfolio.Size_In_USD = tostring(aResponse["market_value"]); end) then
				GET_Portfolio.Size_In_USD = tostring(aResponse["market_value"]);
			else GET_Accounts.Size_In_USD = nil; end
			if pcall(function () GET_Portfolio.Extened_Hours_Size_In_USD = tostring(aResponse["extended_hours_market_value"]); end) then
				GET_Portfolio.Extened_Hours_Size_In_USD = tostring(aResponse["extended_hours_market_value"]);
			else GET_Accounts.Extened_Hours_Size_In_USD = nil; end
			if not string.match(GET_Portfolio.Extened_Hours_Size_In_USD, "%a") then
				GET_Portfolio.Size_In_USD = GET_Portfolio.Extened_Hours_Size_In_USD;
			end
	
			return GET_Portfolio;
		else
			Send_Notification("Alert", "", 0, "Parse_Robinhood_Response() Failed | In Sub Else Clause", core.now(), "");
		end	
	else
		Send_Notification("Alert", "", 0, "Parse_Robinhood_Response() Failed | In Else Clause", core.now(), "");
	end	
end


--------------------------------------------------------------------------------------------
-- Parse Oanda Response Function
--------------------------------------------------------------------------------------------

function Parse_Oanda_Response(aEndpoint, aEndpoint_Type, aResponse)
	if aEndpoint == "Account" then
		if aEndpoint_Type == "GET_Summary" then
			local GET_Summary = {};
			if pcall(function () GET_Summary.NAV = tostring(aResponse["account"]["NAV"]); end) then
				GET_Summary.NAV = tostring(aResponse["account"]["NAV"]);
			else GET_Summary.NAV = nil; end
			if pcall(function () GET_Summary.Size_In_USD = tostring(aResponse["account"]["positionValue"]); end) then 
				GET_Summary.Size_In_USD = tostring(aResponse["account"]["positionValue"]);
			else GET_Summary.Size_In_USD = nil; end
			if pcall(function () GET_Summary.Unrealized_PL = tostring(aResponse["account"]["unrealizedPL"]); end) then 
				GET_Summary.Unrealized_PL = tostring(aResponse["account"]["unrealizedPL"]);
			else GET_Summary.Unrealized_PL = nil; end
			return GET_Summary;
		else
			Send_Notification("Alert", "", 0, "Parse_Oanda_Response() Failed | In Else Clause", core.now(), "");
		end
	else
		Send_Notification("Alert", "", 0, "Parse_Oanda_Response() Failed | In Else Clause", core.now(), "");
	end
end


--------------------------------------------------------------------------------------------
-- Send Notification Function
--------------------------------------------------------------------------------------------

function Send_Notification(aType, aSymbol, aOpen, aMessage, aTime)
	if aType == "Alert" then
		terminal:alertMessage(aSymbol, aOpen, aMessage, aTime);
	elseif aType == "Trace" then
		core.host:trace(aMessage);
	else
		core.host:trace("Send_Notification() Failed | In Else Clause");
	end
end


--------------------------------------------------------------------------------------------
-- Formatting Functions
--------------------------------------------------------------------------------------------

function Format_Precision(aInput, aDecimals)
	return string.format("%." .. aDecimals .. "f", aInput);
end


function Format_Percentage(aInput, aDecimals)
	return string.format("%." .. aDecimals .. "f", aInput) .. "%";
end


function Format_Leverage(aInput, aDecimals)
	return string.format("%." .. aDecimals .. "f", aInput) .. ":1";
end


function Format_Financial(aInput, aDecimals)
	-- Sourced from http://www.gammon.com.au/forum/?id=7805
	aInput = string.format("%." .. aDecimals .. "f", aInput);
	
	local aResult = "";
	local aSign, aBefore, aAfter = string.match(tostring(aInput), "^([%+%-]?)(%d*)(%.?.*)$")
	while string.len(aBefore) > 3 do
		aResult = "," .. string.sub(aBefore, -3, -1) .. aResult;
		aBefore = string.sub(aBefore, 1, -4);
	end
	
	return aSign .. "$" .. aBefore .. aResult .. aAfter;
end


function Format_Color(aInput)
	aInput = tonumber(aInput);
	if aInput == nil then
		return Format.Neutral;
	elseif aInput > 0 then
		return Format.Positive;
	elseif aInput < 0 then
		return Format.Negative;
	else
		return Format.Neutral;
	end
end


--------------------------------------------------------------------------------------------
-- Async Operations Function
--------------------------------------------------------------------------------------------

function AsyncOperationFinished(aReference, aSuccess, aMessage, aMessage1, aMessage2)
	if aReference == 100 then
		if not Robinhood.TFA_Mode then
			Get_Robinhood_API_Token();
		else
			Get_Robinhood_API_Token_TFA_Step_2();
		end
		Get_Robinhood_Portfolio_URL();
		Get_Robinhood_Account_Data();
		Get_Oanda_Account_Data();
		Get_FXCM_Account_Data();
		core.host:execute("killTimer", Timer.Initialized);
	elseif aReference == 200 then
		Get_Robinhood_Account_Data();
		Get_Oanda_Account_Data();
		Get_FXCM_Account_Data();
	elseif aReference == 500 then
		core.host:execute("killTimer", Timer.Send_Request);
	end
end
