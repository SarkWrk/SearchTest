local UI = script.Parent.UI

local log_level = game:GetService("ReplicatedStorage").Shared.LogLevel.Value

game:GetService("ReplicatedStorage").Shared.LogLevel.Changed:Connect(function(value)
    print(script:GetFullName() .. " log level changed to " .. value)
    log_level = value
end)

function RegeneratePath() : ()
    if log_level >= 1 then
        print("Regenerating path")
    end

    game:GetService("ReplicatedStorage").Shared.Regenerate:Fire()
end

function ShowLabelsSwitch(value : boolean) : ()
    if log_level >= 1 then
        print("Changling show labels to " .. tostring(not game:GetService("ReplicatedStorage").Shared.ShowLabels.Value))
    end
    game:GetService("ReplicatedStorage").Shared.ShowLabels.Value = not game:GetService("ReplicatedStorage").Shared.ShowLabels.Value
end

function ChangeValue(text : string, valueToChange : number, valueType : "uint"|"int"|"ufloat"|"float") : ()
    -- Logging purposes
    local value_chosen = ""

    if valueToChange == 0 then
        value_chosen = "start position"
    elseif valueToChange == 1 then
        value_chosen = "end position"
    elseif valueToChange == 2 then
        value_chosen = "log level"
    elseif valueToChange == 3 then
        value_chosen = "tick delay"
    elseif valueToChange == 4 then
        value_chosen = "walkspeed"
    end

    local cleanedText = ""

    if log_level >= 2 then
        print("Inputted text (" .. value_chosen .."): " .. text)
    end

    -- Remove unwanted characters
    for _, character in pairs(text:split("")) do
        if tonumber(character) then
            cleanedText = cleanedText .. character
        end

        if character == "," then
            cleanedText = cleanedText .. character
        end

        if valueType == ("float" or "ufloat") then
            if character == "." then
                cleanedText = cleanedText .. character
            end
        end

        if valueType == ("float" or "int") then
            if character == "-" then
                cleanedText = cleanedText .. character
            end
        end
    end

    if log_level >= 2 then
        print("Cleaned text (" .. value_chosen .."): " .. cleanedText)
    end

    local value_one, value_two, value_three = nil, nil, nil

    local choordsSplit = cleanedText:split(",")

    value_one = tonumber(choordsSplit[1]) or 0
    value_two = tonumber(choordsSplit[2]) or 0
    value_three = tonumber(choordsSplit[3]) or 0

    if log_level >= 2 then
        if valueToChange == (1 or 2) then
            print("New coordinate (" .. value_chosen .."): " .. value_one .. ", " .. value_two .. ", " .. value_three)
        elseif valueToChange == 2 then
            print("New level (" .. value_chosen .."): " .. value_one)
        end
    end

    -- Change start position
    if valueToChange == 0 then
        if log_level >= 1 then
           print("Updated start position") 
        end
        game:GetService("ReplicatedStorage").Shared.StartPosition.Value = Vector3.new(value_one, value_two, value_three)
    -- Change end position
    elseif valueToChange == 1 then
        print("Updated end position")
        game:GetService("ReplicatedStorage").Shared.EndPosition.Value = Vector3.new(value_one, value_two, value_three)
    -- Change log level
    elseif valueToChange == 2 then
        print("Updated log level")
        game:GetService("ReplicatedStorage").Shared.LogLevel.Value = value_one
    -- Change tick delay
    elseif valueToChange == 3 then
        print("Updated delay interval")

        -- Prevent the game from dying
        if value_one == nil or value_one == 0 then
            value_one = math.huge
        end

        game:GetService("ReplicatedStorage").Shared.TickDelay.Value = value_one
    -- Change log level
    elseif valueToChange == 4 then
        print("Updated WalkSpeed")
        game:GetService("Players").LocalPlayer.Character:WaitForChild("Humanoid").WalkSpeed = value_one
    end
end

UI.RegenerateButton.Activated:Connect(RegeneratePath)
UI.SHowLabelsButton.Activated:Connect(ShowLabelsSwitch)

UI.StartPosition:GetPropertyChangedSignal("Text"):Connect(function()
    ChangeValue(UI.StartPosition.Text, 0, "float")
end)
UI.EndPosition:GetPropertyChangedSignal("Text"):Connect(function()
    ChangeValue(UI.EndPosition.Text, 1, "float")
end)

UI.UpdateLogLevel:GetPropertyChangedSignal("Text"):Connect(function()
    ChangeValue(UI.UpdateLogLevel.Text, 2, "int")
end)

UI.UpdateDelay:GetPropertyChangedSignal("Text"):Connect(function()
    ChangeValue(UI.UpdateDelay.Text, 3, "uint")
end)

UI.UpdateWalkspeed:GetPropertyChangedSignal("Text"):Connect(function()
    ChangeValue(UI.UpdateWalkspeed.Text, 4, "ufloat")
end)