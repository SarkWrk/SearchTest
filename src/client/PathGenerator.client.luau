-- Services / Service-adjacents
local replicated_storage_objects = game:GetService("ReplicatedStorage").Shared
local debrisService = game:GetService("Debris")

-- Other stuff
local log_level = replicated_storage_objects.LogLevel.Value
local tick_delay = replicated_storage_objects.TickDelay.Value
local path_interrupt, path_generating = false, false

replicated_storage_objects.LogLevel.Changed:Connect(function(value)
    print(script:GetFullName() .. " log level changed to " .. value)

    log_level = value
end)

replicated_storage_objects.TickDelay.Changed:Connect(function(value)
    print(script:GetFullName() .. " delay changed to " .. value)

    tick_delay = value
end)

--[[
Table used to log the average time it takes for a node to be checked and created.
Used when log_level >= 2
]]
local node_creation_times : {{node_number : number, time : number}} = {}
local node_creation_times_configuration = {
    grouped_average_chunk_size = 10
}

--[[
A table containing config settings for path creation
]]
local path_configurations = {}
path_configurations.path_stud_size = 1
path_configurations.success_within_stud_range = 0.5
path_configurations.validation_size_adjustment = 1-9*math.pow(10, -5)

path_configurations.agents = {}
path_configurations.agents.max_jump_height = 7 -- in studs
path_configurations.agents.max_jump_distance = 11 -- in studs

--Stores the path that gets created
local pathFolder = Instance.new("Folder")
pathFolder.Name = "Path"
pathFolder.Parent = workspace

-- Stores instances that are used to show important parts of how the path is being generated
local objectVisualiserFolder = Instance.new("Folder")
objectVisualiserFolder.Name = "Visualiser"
objectVisualiserFolder.Parent = workspace

-- Shows where the path starts generating from
local startPositionIndicator = Instance.new("Part")
startPositionIndicator.Name = "StartPosition"
startPositionIndicator.Size = Vector3.new(1, 1, 1)
startPositionIndicator.Transparency = 0.5
startPositionIndicator.Color = Color3.new(0, 1, 0)
startPositionIndicator.Material = Enum.Material.Neon
startPositionIndicator.Position = Vector3.new(0, 0, 0)
startPositionIndicator.Anchored = true
startPositionIndicator.Parent = objectVisualiserFolder

-- Shows where the path will end
local endPositionIndicator = Instance.new("Part")
endPositionIndicator.Name = "EndPosition"
endPositionIndicator.Size = Vector3.new(1, 1, 1)
endPositionIndicator.Transparency = 0.5
endPositionIndicator.Color = Color3.new(0, 0, 1)
endPositionIndicator.Material = Enum.Material.Neon
endPositionIndicator.Position = Vector3.new(0, 0, 0)
endPositionIndicator.Anchored = true
endPositionIndicator.Parent = objectVisualiserFolder

--Highlights the start indicator
local startHighlight = Instance.new("Highlight")
startHighlight.FillTransparency = 1
startHighlight.OutlineTransparency = 0
startHighlight.OutlineColor = Color3.new(1, 1, 1)
startHighlight.Adornee = startPositionIndicator
startHighlight.Parent = startPositionIndicator

-- Highlights the end indicator
local endHighlight = Instance.new("Highlight")
endHighlight.FillTransparency = 1
endHighlight.OutlineTransparency = 0
endHighlight.OutlineColor = Color3.new(1, 1, 1)
endHighlight.Adornee = endPositionIndicator
endHighlight.Parent = endPositionIndicator

--[[
A table that contains presets for object creations when generating the path
]]
local archetypes = {}

-- Archetype for indicators on a path part
archetypes.distplayArchetype = Instance.new("TextLabel")
archetypes.distplayArchetype.Size = UDim2.new(1, 0, 1, 0)
archetypes.distplayArchetype.TextScaled = true
archetypes.distplayArchetype.BackgroundColor3 = Color3.new(1, 1, 1)
archetypes.distplayArchetype.TextColor3 = Color3.new(0, 0, 0)
archetypes.distplayArchetype.BorderSizePixel = 0

-- Archetype for the surface gui that the indicator displays go on
archetypes.surfaceArchetype = Instance.new("SurfaceGui")
archetypes.surfaceArchetype.Brightness = 1
archetypes.surfaceArchetype.MaxDistance = 10

-- Archetype for nodes
archetypes.nodeArchetype = Instance.new("Part")
archetypes.nodeArchetype.Color = Color3.new(0.745098, 0.874510, 0.168627)
archetypes.nodeArchetype.Size = Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, path_configurations.path_stud_size)
archetypes.nodeArchetype.Anchored = true
archetypes.nodeArchetype.CanCollide = false
archetypes.nodeArchetype.Transparency = 0.25
archetypes.nodeArchetype.Material = Enum.Material.Glass


replicated_storage_objects.ShowLabels.Changed:Connect(function(value : boolean)
    archetypes.surfaceArchetype.Enabled = value
end)


--[[
Sorts the part_index dictionary
N.B. The parts that are closest to the start location will be put last
]]
function SortByFurthest(value_one : {Position : Vector3, DistanceFromStart : number, Part : Part}, value_two : {Position : Vector3, DistanceFromStart : number, Part : Part})
    if value_one.DistanceFromStart > value_two.DistanceFromStart then
        return true
    end

    return false
end

function PathCalculation(startPosition, endPosition, partIndex)
    local start_time = tick()

    table.sort(partIndex, SortByFurthest)

    if log_level >= 1 then
        print("Finished generating path in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end
    
    path_generating = false
end

--[[
Creates a part (and labels for the part) at a location on the path
]]
function CreatePathPart(nodeNumber : number, location : Vector3, importantPositions : {start_position : Vector3, end_position : Vector3}, filters : {["inPartCheck"] : OverlapParams, ["landedChek"] : RaycastParams}, nextSearchPoints : {Part}, indexOfParts : {{Position : Vector3, DistanceFromStart : number, Part : Part}}, jumpedFromLocation : Vector3, airTime : number?)    
    local distance = math.floor((location - importantPositions.start_position).Magnitude)

    if airTime == nil then
        airTime = 0
    end

    local node = Instance.fromExisting(archetypes.nodeArchetype)
    node.Position = location
    node.Name = nodeNumber

    local distanceDisplay = Instance.fromExisting(archetypes.surfaceArchetype)
    distanceDisplay.Face = "Top"

    local distanceIndicator = Instance.fromExisting(archetypes.distplayArchetype)
    distanceIndicator.Text = distance
    distanceIndicator.Parent = distanceDisplay

    local airTimeDisplay = Instance.fromExisting(archetypes.surfaceArchetype)
    airTimeDisplay.Face = "Front"

    local airTimeIndicator = Instance.fromExisting(archetypes.distplayArchetype)
    airTimeIndicator.Text = airTime
    airTimeIndicator.Parent = airTimeDisplay

    distanceDisplay.Parent = node
    airTimeDisplay.Parent = node

    node:SetAttribute("Distance", distance)
    node:SetAttribute("Air_Time", airTime)

    if airTime == 0 then
        node:SetAttribute("On_Ground", true)
    else
        node:SetAttribute("On_Ground", false)
        node:SetAttribute("Jump_Location", jumpedFromLocation)
    end

    
    for _, param in pairs(filters) do
        param:AddToFilter(node)
    end

    table.insert(nextSearchPoints, node)

    local index_value = {}
    index_value.Position = location
    index_value.DistanceFromStart = distance
    index_value.Part = node

    table.insert(indexOfParts, index_value)

    node.Parent = pathFolder

    if log_level >= 4 then
        print("Created indicator #" .. node.Name .. "\nDistance: " .. node:GetAttribute("Distance") .. " / Air time: " .. node:GetAttribute("Air_Time"))
    end
end

--[[
Validates if a location can be used for the path
]]
function ValidateLocation(position : Vector3, isInPartParams: OverlapParams, checked_locations : {Vector3}) : boolean
    if table.find(checked_locations, position) then
        return false
    end

    table.insert(checked_locations, position)

    local is_position_in_part_check = workspace:GetPartBoundsInBox(CFrame.new(position), path_configurations.validation_size_adjustment*Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, path_configurations.path_stud_size), isInPartParams)

    if table.maxn(is_position_in_part_check) > 0 then
        if log_level >= 3 then
            print("(" .. position.X .. ", " .. position.Y .. ", " .. position.Z .. ") is now checked and is not a viable position because it intersects " .. is_position_in_part_check[1]:GetFullName())
        end
        
        return false
    end

    if log_level >= 3 then
        print("(" .. position.X .. ", " .. position.Y .. ", " .. position.Z .. ") is now checked and is a viable position")
    end

    return true
end

--[[
Checks whether a point exceeds the limits of the path configurations
]]
function CheckPathLimits(position : Vector3, part_origin : Part, raycastParams : RaycastParams) : (boolean, number)
    local air_time = tonumber(part_origin:GetAttribute("Air_Time")) :: number?
    local jumped_from_location = part_origin:GetAttribute("Jump_Locaiton") :: Vector3?
    local is_going_down = false
    
    -- Air time check
    -- Check whether the previous point was on the ground
    if part_origin:GetAttribute("On_Ground") == true then
        -- If it is then if the next position is not on the same plane, then the air time increases
        if position.Y > part_origin.Position.Y then
            air_time += 1
        elseif position.Y < part_origin.Position.Y then
            air_time += 1
        end
    else
        -- Otherwise, check if the new position will place the path back on the ground
        -- If it will then set the air time back to 0
        if workspace:Raycast(position, position + Vector3.new(0, -path_configurations.path_stud_size*1.5, 0), raycastParams) then
            air_time = 0
        -- Otherwise, increase the air time and check if the position is below the previous point
        else
            air_time += 1

            if position.Y < part_origin.Position.Y then
                is_going_down = true
            end
        end
    end

    -- If the new position is going up and is going higher than the agent can reasonably go, don't let the algrithm create a point there
    if is_going_down == false and air_time > path_configurations.agents.max_jump_height then
        if jumped_from_location then
            if position.Y-jumped_from_location.Y > path_configurations.agents.max_jump_height then
                return false, air_time
            end
        end
    end

    -- Check if the part is too far to jump to
    if jumped_from_location then
        local y_difference = position.Y - jumped_from_location.Y
        local distance_from_jump_location = (position-jumped_from_location).Magnitude

        if distance_from_jump_location > path_configurations.agents.max_jump_distance + y_difference then
            return false, air_time
        end
    end

    return true, air_time
end

--[[
Returns every vector from a 3x3x3 cube sat on a position ignoring the centre
If canJump is falase, then then the upper portion of the cube will not be returned
]]
function NextPositions(originPosition : Vector3, canJump : boolean) : {Vector3}
    if canJump == true then
        local newPositionsTable = {
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, 0),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, 0),
            originPosition + Vector3.new(0, path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(0, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(-path_configurations.path_stud_size, path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, path_configurations.path_stud_size),
        }
    
        return newPositionsTable
    else
        local newPositionsTable = {
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, 0),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, 0),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(0, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, 0, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, 0, path_configurations.path_stud_size),
            originPosition + Vector3.new(path_configurations.path_stud_size, -path_configurations.path_stud_size, -path_configurations.path_stud_size),
            originPosition + Vector3.new(-path_configurations.path_stud_size, -path_configurations.path_stud_size, path_configurations.path_stud_size),
        }

        return newPositionsTable
    end
end

function Algrithm(startPosition: Vector3, endPosition: Vector3)
    local reached_destination: boolean = false
    local start_time: number = tick()
    local checked_locations : {Vector3} = {startPosition, endPosition}
    local next_parts_to_check : {Part} = {}
    local part_index = {} :: {{Position : Vector3, DistanceFromStart : number, Part : Part}}

    -- Tell the script that the path is being generated (in-case manual interrupt)
    path_generating = true

    -- Used in ValidateLocation()
    local isInPartParams = OverlapParams.new()
    isInPartParams.RespectCanCollide = true
    isInPartParams.FilterDescendantsInstances = {startPositionIndicator, endPositionIndicator}

    local landedCheckParams = RaycastParams.new()
    landedCheckParams.RespectCanCollide = true
    landedCheckParams.FilterDescendantsInstances = {startPositionIndicator, endPositionIndicator}

    for _, player in pairs(game:GetService("Players"):GetPlayers()) do
        isInPartParams:AddToFilter(player.Character)
        landedCheckParams:AddToFilter(player.Character)
    end

    local node_number = 0

    CreatePathPart(node_number, startPosition, {start_position = startPosition, end_position = endPosition}, {["inPartCheck"] = isInPartParams, ["landedChek"] = landedCheckParams}, next_parts_to_check, part_index, startPosition, 1)

    while reached_destination == false do
        -- Sort the table so that the closest parts are chosen first
        if (node_number % 5 == 0) or (node_number <= 500) then
            game:GetService("RunService").Heartbeat:Wait()
            table.sort(next_parts_to_check, function(part_one : Part, part_two : Part)
                if (part_one.Position-endPosition).Magnitude < (part_two.Position-endPosition).Magnitude then
                    return true
                end

                return false
            end)
        end

        local next_part = next_parts_to_check[1]

        local can_jump = false

        if next_part == nil then
            break
        end

        if path_interrupt == true then
            break
        end

        if next_part:GetAttribute("On_Ground") == true then
            can_jump = true
        else
            if next_part:GetAttribute("Air_Time") <= 5 then
                can_jump = true
            end
        end

        for _, position : Vector3 in pairs(NextPositions(next_part.Position, can_jump)) do
            -- Logging purposes
            local node_start_time = tick()

            -- Check if the position is close enough to the end goal for it to count as reaching it
            if (position-endPosition).Magnitude <= path_configurations.success_within_stud_range then
                reached_destination = true
                break
            end

            debug.profilebegin("ValidateLocation")
            local viableLocation = ValidateLocation(position, isInPartParams, checked_locations)
            debug.profileend()

            if viableLocation == false then
                continue
            end

            debug.profilebegin("CheckPathLimits")
            local success, air_time = CheckPathLimits(position, next_part, landedCheckParams)
            debug.profileend()

            if success == false then
                continue
            end

            node_number += 1

            debug.profilebegin("CreatePathPart")
            CreatePathPart(node_number, position, {start_position = startPosition, end_position = endPosition}, {["inPartCheck"] = isInPartParams, ["landedChek"] = landedCheckParams}, next_parts_to_check, part_index, next_part.Position, air_time)
            debug.profileend()

            table.insert(node_creation_times, {["node_number"] = node_number, ["time"] = tick()-node_start_time})
        end
        table.remove(next_parts_to_check, 1)

        if node_number % tick_delay == 0 then
            game:GetService("RunService").Heartbeat:Wait()
        end
    end

    if reached_destination == true then
        if log_level >= 1 then
            print("Reached end point in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
        end

        for i, node : Part in pairs(pathFolder:GetChildren()) do
            node.Color = Color3.new(0.172549, 0.180392, 0.600000)
            node.Transparency = 0.5

            if i % (tick_delay*6) == 0 then
                task.wait()
            end
        end

        PathCalculation(startPosition, endPosition, part_index)
    else
        if path_interrupt == true then
            path_interrupt = false
            print("Path generation manually interrupted")
        else
            warn("Ran out of viable parts")
        end
    end
end

--[[
Starts the sequence for generating a path
]]
function StartSequence()
    if path_interrupt == true then
        return
    end

    for i, node in pairs(pathFolder:GetChildren()) do
        debrisService:AddItem(node, 0)
        if i % (tick_delay*6) == 0 then
            task.wait()
        end
    end

    if path_generating == true then
        path_interrupt = true
    end

    while path_interrupt == true do
        task.wait()
    end

    table.clear(node_creation_times)

    local start_time = tick()
    local start_position = replicated_storage_objects.StartPosition.Value
    local end_position = replicated_storage_objects.EndPosition.Value

    if log_level >= 1 then
        print("Starting path creation")
    end

    startPositionIndicator.Position = start_position
    endPositionIndicator.Position = end_position

    -- debug.profilebegin("Algrithm")
    Algrithm(start_position, end_position)
    -- debug.profileend()

    if log_level >= 1 then
        print("Finished creating path in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end

    if log_level >= 2 then
        local total_time = 0
        for _, subtable in pairs(node_creation_times) do
            total_time += subtable.time
        end

        local average = math.round((total_time / table.maxn(node_creation_times))*1000)/1000

        print("Average node creation time: " .. average .. "s" .. "\nActual: " .. total_time/table.maxn(node_creation_times) .. "\nTotal time: " .. total_time)
    end

    if log_level >= 3 then
        local grouped_total_time = 0

        for i, subtable in pairs(node_creation_times) do
            grouped_total_time += subtable.time

            if i % node_creation_times_configuration.grouped_average_chunk_size == 0 then
                local average = math.round((grouped_total_time / node_creation_times_configuration.grouped_average_chunk_size)*1000)/1000
        
                print("Average node creation time between nodes " .. i-node_creation_times_configuration.grouped_average_chunk_size .. "-" .. i .. ": " .. average .. "s")
            end
        end
    end
end

replicated_storage_objects.Regenerate.Event:Connect(StartSequence)

game:GetService("Players").LocalPlayer.CharacterAdded:Wait()

-- replicated_storage_objects.Regenerate:Fire()