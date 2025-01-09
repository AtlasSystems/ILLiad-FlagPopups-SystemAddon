luanet.load_assembly("System.Windows.Forms");
luanet.load_assembly("log4net");

local Types = {};
Types["System.Windows.Forms.MessageBox"] = luanet.import_type("System.Windows.Forms.MessageBox");
Types["System.Windows.Forms.MessageBoxButtons"] = luanet.import_type("System.Windows.Forms.MessageBoxButtons");
Types["System.Windows.Forms.DialogResult"] = luanet.import_type("System.Windows.Forms.DialogResult");
Types["log4net.LogManager"] = luanet.import_type("log4net.LogManager");

local log = Types["log4net.LogManager"].GetLogger("AtlasSystems.Addons.FlagPopups");

local Settings = {};
Settings.BorrowingCheckInFromLenderEnabled = GetSetting("BorrowingCheckInFromLenderEnabled");
Settings.BorrowingCheckInFromCustomerEnabled = GetSetting("BorrowingCheckInFromCustomerEnabled");
Settings.DocumentDeliveryMarkFoundEnabled = GetSetting("DocumentDeliveryMarkFoundEnabled");
Settings.LendingMarkFoundEnabled = GetSetting("LendingMarkFoundEnabled");
Settings.LendingReturnsEnabled = GetSetting("LendingReturnsEnabled");
Settings.FlagsToDisplay =  '"' .. GetSetting("FlagsToDisplay"):lower():gsub('%s*,%s*', ','):gsub(',', '","') .. '"';
Settings.FlagsToRemove = '"' .. GetSetting("FlagsToRemove"):lower():gsub('%s*,%s*', ','):gsub(',', '","') .. '"';
Settings.FlagsToChoose = '"' .. GetSetting("FlagsToChoose"):lower():gsub('%s*,%s*', ','):gsub(',', '","') .. '"';

function Init()
	if Settings.BorrowingCheckInFromLenderEnabled then
		RegisterSystemEventHandler("BorrowingRequestCheckedInFromLibrary", "BorrowingCheckedInFromLender");
	end
	if Settings.BorrowingCheckInFromCustomerEnabled then
		RegisterSystemEventHandler("BorrowingRequestCheckedInFromCustomer", "BorrowingCheckedInFromPatron");
	end
	if Settings.DocumentDeliveryMarkFoundEnabled then
		RegisterSystemEventHandler("DocumentDeliveryRequestCheckOut", "DocDelRequestMarkedFound");
	end
	if Settings.LendingMarkFoundEnabled then
		RegisterSystemEventHandler("LendingRequestCheckOut", "LendingRequestMarkedFound");
	end
	if Settings.LendingReturnsEnabled then
		RegisterSystemEventHandler("LendingRequestCheckIn", "LendingRequestReturned");
	end	
end

function BorrowingCheckedInFromLender()
	HandleFlags();
end

function BorrowingCheckedInFromPatron()
	HandleFlags();
end

function DocDelRequestMarkedFound()
	HandleFlags();
end

function LendingRequestMarkedFound()
	HandleFlags();
end

function LendingRequestReturned()
	HandleFlags();
end

function HandleFlags()
	local transactionNumber = GetFieldValue("Transaction", "TransactionNumber");
	local flagNames = GetFlagNames(transactionNumber);

	if flagNames == "error" or #flagNames == 0 then
		return;
	end

	local messageBox = Types["System.Windows.Forms.MessageBox"];
	local messageBoxButtons = Types["System.Windows.Forms.MessageBoxButtons"];
	local dialogResult = Types["System.Windows.Forms.DialogResult"];

	for i = 1, #flagNames do
		local flagNameToMatch = flagNames[i]:lower();

		local removalMessage;

		if Settings.FlagsToRemove:find(flagNameToMatch) then
			removalMessage = "Flag will be removed.";
			ExecuteCommand("RemoveTransactionFlag", {transactionNumber, flagNames[i]});
		else
			removalMessage = "Flag will not be removed.";
		end

		if Settings.FlagsToChoose:find(flagNameToMatch) then
			local messageBoxResult = messageBox.Show("Request " .. transactionNumber .. " is flagged with [" .. flagNames[i] .. "].\n\n\n\n\tRemove flag?", "Request is Flagged", messageBoxButtons.YesNo);
			if messageBoxResult == dialogResult.Yes then
				ExecuteCommand("RemoveTransactionFlag", {transactionNumber, flagNames[i]});
			end
		elseif Settings.FlagsToDisplay:find(flagNameToMatch) then
			messageBox.Show("Request " .. transactionNumber .. " is flagged with [" .. flagNames[i] .. "].\n\n\n\n\t" .. removalMessage, "Request is Flagged");
		end
	end
end

function GetFlagNames(transactionNumber)
	local connection = CreateManagedDatabaseConnection();

	local success, flagNamesOrErr = pcall(function()
		connection:Connect();

		local queryString = "SELECT FlagName FROM CustomFlags INNER JOIN TransactionFlags ON TransactionFlags.FlagID = CustomFlags.ID WHERE TransactionNumber = '" .. transactionNumber .. "'";
		
		log:Debug("Querying the database with querystring: " .. queryString);
		connection.QueryString = queryString;
		
		local queryResults = connection:Execute();

		local flagNames = {};
		if (queryResults.Rows.Count > 0) then
			for i = 0, queryResults.Rows.Count - 1 do
				flagNames[#flagNames+1] = queryResults.Rows:get_Item(i):get_Item("FlagName");
			end
		end

		return flagNames;
	end);

	connection:Dispose();

	if not success then
		log:Error("An error occurred when retrieving custom flag info from the database: " .. tostring(TraverseError(flagNamesOrErr)));
		return "error";
	end

	return flagNamesOrErr;
end

function TraverseError(e)
    if not e.GetType then
        -- Not a .NET type
        return e;
    else
        if not e.Message then
            -- Not a .NET exception
            return e;
        end
    end

    log:Debug(e.Message);

    if e.InnerException then
        return TraverseError(e.InnerException);
    else
        return e.Message;
    end
end

function OnError(err)
    log:Error(tostring(TraverseError(err)));
end