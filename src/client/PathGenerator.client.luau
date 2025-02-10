-- Services / Service-adjacents
local replicated_storage_objects = game:GetService("ReplicatedStorage").Shared
local debrisService = game:GetService("Debris")
local runService = game:GetService("RunService")

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
A table containing config settings for path creation
]]
local path_configurations = {}
path_configurations.path_node_size = 1 -- in studs
path_configurations.success_within_stud_range = 0.5 -- in studs
path_configurations.validation_size_adjustment = 1-9*math.pow(10, -5)
path_configurations.create_node_labels = replicated_storage_objects.ShowLabels.Value
path_configurations.key_node_rate = 500

path_configurations.agents = {}
path_configurations.agents.max_jump_height = 6 -- in studs
path_configurations.agents.max_jump_distance = 11 -- in studs

replicated_storage_objects.ShowLabels.Changed:Connect(function(value : boolean)
    path_configurations.create_node_labels = value
end)

--[[
A table containin config settings for visualisation settings
]]
local visualisation_configurations = {}
visualisation_configurations.refresh_delay = 0.01 -- in seconds
visualisation_configurations.progressGUIPath = nil :: Frame?
visualisation_configurations.nodesCheckedGUIPath = nil :: TextLabel?
visualisation_configurations.calculationPhaseGUIPath = nil :: TextLabel?
visualisation_configurations.node_creation_text = "Node creation progress:"
visualisation_configurations.nodes_checked_text = "Nodes checked:"
visualisation_configurations.calculation_phase_text = "Calculation phase:"

game:GetService("Players").LocalPlayer.CharacterAdded:Connect(function()
    visualisation_configurations.progressGUIPath = game:GetService("Players").LocalPlayer.PlayerGui.UI.NodeCreationDisplay
    visualisation_configurations.nodesCheckedGUIPath = game:GetService("Players").LocalPlayer.PlayerGui.UI.NodesChecked
    visualisation_configurations.calculationPhaseGUIPath = game:GetService("Players").LocalPlayer.PlayerGui.UI.CalculationPhase
end)

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
archetypes.nodeArchetype.Color = Color3.new(0.172549, 0.180392, 0.600000)
archetypes.nodeArchetype.Size = Vector3.new(path_configurations.path_node_size, path_configurations.path_node_size, path_configurations.path_node_size)
archetypes.nodeArchetype.Anchored = true
archetypes.nodeArchetype.CanCollide = false
archetypes.nodeArchetype.Transparency = 0.5
archetypes.nodeArchetype.Material = Enum.Material.Glass

-- Types, for simplicity
type node_information = {
    node_number : number,
    properties : {
        position : Vector3,
        color : Color3,
        material : Enum.Material | string,
    },
    attributes : {
        air_time : number,
        distance : number,
        on_ground : boolean,
        key_node : boolean,
        jump_location : Vector3?,
    }
}

type waypoint = {
        position : Vector3,
        original_node_number : number,
        jump : boolean,
    }

function TrialPath(waypoints :  {waypoint})
    local character = replicated_storage_objects.Parent.rig:Clone()
    character:PivotTo(CFrame.new(waypoints[1].position + Vector3.new(0, 3, 0)))
    character.Parent = workspace
    local humanoid : Humanoid = character.Humanoid

    for _, v : Instance in pairs(character:GetDescendants()) do
        if v:IsA("Script") then
            v:Destroy()
        elseif v:IsA("LocalScript") then
            v:Destroy()
        elseif v:IsA("ModuleScript") then
            v:Destroy()
        end
    end

    for i, waypoint : waypoint in pairs(waypoints) do
        humanoid:MoveTo(waypoint.position)
        if waypoint.jump == true then
            humanoid.Jump = true
        end

        humanoid.MoveToFinished:Wait()
    end

    task.wait(2)

    character:Destroy()
end

--[[
Creates a part (and labels for the part) at a location on the path
]]
function CreatePathPart(node_information : node_information) : Part
    local node = Instance.fromExisting(archetypes.nodeArchetype)
    node.Position = node_information.properties.position
    node.Name = node_information.node_number

    if path_configurations.create_node_labels == true then
        local distanceDisplay = Instance.fromExisting(archetypes.surfaceArchetype)
        distanceDisplay.Face = "Top"

        local distanceIndicator = Instance.fromExisting(archetypes.distplayArchetype)
        distanceIndicator.Text = math.floor(node_information.attributes.distance)
        distanceIndicator.Parent = distanceDisplay

        local airTimeDisplay = Instance.fromExisting(archetypes.surfaceArchetype)
        airTimeDisplay.Face = "Front"

        local airTimeIndicator = Instance.fromExisting(archetypes.distplayArchetype)
        airTimeIndicator.Text = node_information.attributes.air_time
        airTimeIndicator.Parent = airTimeDisplay

        distanceDisplay.Parent = node
        airTimeDisplay.Parent = node
    end

    for attribute_name, attribute_value in pairs(node_information.attributes) do
        if attribute_name == "distance" then
            node:SetAttribute(tostring(attribute_name), math.floor(attribute_value))
        else
            node:SetAttribute(tostring(attribute_name), attribute_value)
        end
    end

    node.Material = node_information.properties.material
    node.Color = node_information.properties.color

    if log_level >= 4 then
        print("Created indicator #" .. node.Name .. "\nDistance: " .. node:GetAttribute("Distance") .. " / Air time: " .. node:GetAttribute("Air_Time"))
    end

    return node
end

--[[
Node visualiser
]]
function NodeVisualiser(nodes : {node_information})
    local start_time = tick()
    local refresh_delay = tick()
    local created_nodes : {Part} = {}
    local at_node = 0

    -- Create a connection to update the ui
    local updateUI = runService.Heartbeat:Connect(function()
        if (tick()-refresh_delay >= visualisation_configurations.refresh_delay) or (at_node == table.maxn(nodes))then
            refresh_delay = tick()
            local progress = at_node/table.maxn(nodes)
            visualisation_configurations.progressGUIPath.ProgressInformation.Text = visualisation_configurations.node_creation_text .. "\n" .. at_node .. "/" .. table.maxn(nodes) .. " (" .. math.floor(progress * 100) .. "%)"
            visualisation_configurations.progressGUIPath.ProgressBar.Bar.Position = UDim2.new(progress - 1, 0, 0, 0)
        end
    end)

    for i, node in pairs(nodes) do
        table.insert(created_nodes, coroutine.wrap(CreatePathPart)(node))

        if i % (tick_delay*4) == 0 then
            runService.Heartbeat:Wait()
        end
        at_node = i

        if path_interrupt == true then
            break
        end
    end

    updateUI:Disconnect()

    local progress = at_node/table.maxn(nodes)
    visualisation_configurations.progressGUIPath.ProgressInformation.Text = visualisation_configurations.node_creation_text .. "\n" .. at_node .. "/" .. table.maxn(nodes) .. " (" .. math.floor(progress * 100) .. "%)"
    visualisation_configurations.progressGUIPath.ProgressBar.Bar.Position = UDim2.new(progress - 1, 0, 0, 0)

    if path_interrupt == false then
        for _, node in pairs(created_nodes) do
            node.Parent = pathFolder
        end
    else
        table.clear(created_nodes)
    end

    if log_level >= 1 then
        print("Finished creating nodes in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end
end

--[[
Sorts the part_index dictionary
N.B. The parts that are closest to the start location will be put last
]]
function ReverseSort<A>(tableToBeReversed : {A}) : {A}
    local new_table = {}

    for i = table.maxn(tableToBeReversed), 1, -1 do
        new_table[table.maxn(tableToBeReversed)+1-i] = tableToBeReversed[i]
    end

    return new_table
end

--[[
Figures out which nodes to consider and which nodes not to consider
]]
function GetImportantKeyNodes(keyNodes : {node_information}) : {node_information}
    local key_nodes_reversed = {}

    for i = table.maxn(keyNodes), 1, -1 do
        key_nodes_reversed[table.maxn(keyNodes)+1-i] = keyNodes[i]
    end

    local organised_key_nodes = {}

    local ignored_values = {
        [1] = true,
        [table.maxn(key_nodes_reversed)] = true,
        [table.maxn(key_nodes_reversed) - 1] = true,
        [table.maxn(key_nodes_reversed) - 2] = true,
    }

    -- Figure out which key nodes to remove
    for i, v in pairs(key_nodes_reversed) do
        if ignored_values[i] then
            table.insert(organised_key_nodes, v)

            continue
        end

        local distanceConsidering : node_information = key_nodes_reversed[i]
        local distancePotentialSkipTo : node_information = key_nodes_reversed[i + 1]
        local decider : node_information = key_nodes_reversed[i + 2]

        local considering_points = 0
        local potential_points = 0

        if distanceConsidering.attributes.distance < distancePotentialSkipTo.attributes.distance then
            considering_points += 1
        else
            potential_points += 1
        end

        local decider_closer = decider.attributes.distance < distancePotentialSkipTo.attributes.distance and true or false

        if math.abs(distanceConsidering.attributes.distance-decider.attributes.distance) < math.abs(distancePotentialSkipTo.attributes.distance-decider.attributes.distance) then
            if decider_closer == true then
                considering_points += 1
            else
                potential_points += 1
            end
        else
            if decider_closer == true then
                potential_points += 1
            else
                considering_points += 1
            end
        end

        if considering_points > potential_points then
            table.insert(organised_key_nodes, v)
        end
    end

    return organised_key_nodes
end

--[[
Groups and sorts generated nodes into subtables based on key nodes
]]
function GroupAndSortNodesByKeyNodes(nodes : {node_information}, keyNodes : {node_information}) : {{node_information}}
    local split_by_key_nodes  : {{node_information}} = {}

    local next_key_node_index = 1
    local next_key_node_node_number = keyNodes[next_key_node_index].node_number

    for _, node : node_information in pairs(nodes) do
        if node.node_number == next_key_node_node_number then
            table.insert(split_by_key_nodes, {node})

            if next_key_node_index < table.maxn(keyNodes) then
                next_key_node_index += 1
                next_key_node_node_number = keyNodes[next_key_node_index].node_number
            end
        elseif node.node_number > next_key_node_node_number then
            continue
        else
            table.insert(split_by_key_nodes[table.maxn(split_by_key_nodes)], node)
        end
    end

    local sorted_nodes : {{node_information}} = {}

    local deep_copy_times_ran = 0

    local function deepCopy<A>(original : {A}) : {A}
        local copy = {}

        deep_copy_times_ran += 1

        for key, value in original do
            copy[key] = type(value) == "table" and deepCopy(value) or value
        end

        if deep_copy_times_ran % 200 == 0 then
            runService.Heartbeat:Wait()
        end

        return copy
    end

    local function Sort(nodesToSort : {node_information}) : {node_information}
        local sorted : {node_information} = deepCopy(nodes)
        table.remove(sorted, 1)

        table.sort(sorted, function(node_one : node_information, node_two : node_information)
            if (node_one.properties.position-nodesToSort[table.maxn(nodesToSort)].properties.position).Magnitude
            < (node_two.properties.position-nodesToSort[table.maxn(nodesToSort)].properties.position).Magnitude then
                return true
            end

            return false
        end)

        table.insert(sorted, 1, nodesToSort[1])

        return sorted
    end

    for _, subgroup : {node_information} in pairs(split_by_key_nodes) do
        table.insert(sorted_nodes, Sort(subgroup))
    end

    return sorted_nodes
end

--[[
Figures out how to direct the path from all the nodes that have been created
]]
function PathCalculation(startPosition : Vector3, endPosition : Vector3, nodeIndex : {node_information}, keyNodes : {node_information}) : {waypoint}
    local start_time = tick()
    
    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nReversing node order..."

    -- Prepare some tables and work in reverse order to figure out how to build the path
    local nodes_sorted = ReverseSort(nodeIndex)
    local key_nodes_sorted = GetImportantKeyNodes(keyNodes)

    if path_interrupt == true then
        path_generating = false
        return {}
    end

    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nGrouping nodes..."

    local split_by_key_nodes : {{node_information}} = GroupAndSortNodesByKeyNodes(nodes_sorted, key_nodes_sorted)

    if path_interrupt == true then
        path_generating = false
        return {}
    end

    local grouped_path : {{node_information}} = {}

    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nFinding path..."

    -- THIS IS THE PATH CALCULATION STEP
    for i, subgroup : {node_information} in pairs(split_by_key_nodes) do
        local temp_table : {node_information} = {}
        local previous_node : node_information = nil
        local comparison_node = subgroup[1]

        for j, node : node_information in pairs(subgroup) do
            if j == 1 then
                table.insert(temp_table, node)
                previous_node = node
                continue
            elseif j == table.maxn(subgroup) then
                table.insert(temp_table, node)
            end

            -- Check for whether the nodes are touching
            if (previous_node.properties.position-node.properties.position).Magnitude > path_configurations.path_node_size*2 then
                continue
            end

            -- Check for distance
            if (previous_node.properties.position-comparison_node.properties.position).Magnitude
                > (node.properties.position-comparison_node.properties.position).Magnitude then
                continue
            end

            table.insert(temp_table, node)
            previous_node = node
        end

        grouped_path[i] = temp_table

        if path_interrupt == true then
            break
        end
    end

    if path_interrupt == true then
        path_generating = false
        return {}
    end

    local path : {node_information} = {}
    local node_numbers : {string} = {}
    local waypoints : {waypoint} = {}

    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nCombining tables..."

    for _, subgroup : {node_information} in pairs(grouped_path) do
        for _, node : node_information in pairs(subgroup) do
            table.insert(path, node)
            table.insert(node_numbers, tostring(node.node_number))

            local waypoint : waypoint = {
                position = node.properties.position,
                original_node_number = node.node_number,
                jump = not node.attributes.on_ground
            }

            table.insert(waypoints, waypoint)
        end

        if path_interrupt == true then
            break
        end
    end
    
    table.sort(waypoints, function(waypoint_one : waypoint, waypoint_two : waypoint)
        if waypoint_one.original_node_number < waypoint_two.original_node_number then
            return true
        end

        return false
    end)

    if path_interrupt == true then
        path_generating = false
        return {}
    end

    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nChanging nodes..."

    for _, node : Part in pairs(pathFolder:GetChildren()) do
        if table.find(node_numbers, node.Name) then
            node.Color = Color3.new(0.000000, 1.000000, 0.298039)
            node.Material = Enum.Material.SmoothPlastic
            node.Transparency = 0.5
        else
            node.Color = Color3.new(0.937255, 1.000000, 0.086275)
            node.Material = Enum.Material.Glass
            node.Transparency = .6
        end
        node:ClearAllChildren()

        if path_interrupt == true then
            break
        end
    end

    if path_interrupt == true then
        path_generating = false
        return {}
    end

    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nDone!"

    if log_level >= 1 then
        print("Finished generating path in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end
    
    path_generating = false

    return waypoints
end

--[[
Validates if a location can be used for the path
]]
function ValidateLocation(position : Vector3, isInPartParams: OverlapParams, checked_locations : {Vector3}) : boolean
    if table.find(checked_locations, position) then
        return false
    end

    table.insert(checked_locations, position)

    local is_position_in_part_check = workspace:GetPartBoundsInBox(CFrame.new(position), path_configurations.validation_size_adjustment*archetypes.nodeArchetype.Size, isInPartParams)

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
function CheckPathLimits(position : Vector3, part_origin : node_information, overlapParams : OverlapParams) : (boolean, number)
    local air_time = tonumber(part_origin.attributes.air_time) :: number?
    local jumped_from_location = part_origin.attributes.jump_location :: Vector3?

    local function CheckIfOnGround() : boolean
        local parts = workspace:GetPartBoundsInBox(CFrame.new(position + Vector3.new(0, -path_configurations.path_node_size, 0)), path_configurations.validation_size_adjustment*archetypes.nodeArchetype.Size, overlapParams)

        if table.maxn(parts) == 0 then
            return false
        end

        return true
    end
    
    -- Air time check
    -- Check whether the previous point was on the ground
    if part_origin.attributes.on_ground == true then
        -- If it is then if the next position is not on the same plane, then the air time increases
        if position.Y > part_origin.properties.position.Y then
            air_time += 1
        elseif position.Y < part_origin.properties.position.Y then
            air_time += 1
        -- Please verify that it's actually on the ground because it can be considered "On_Ground" even when it's not!?!?!?!?!?!?
        elseif not CheckIfOnGround() then
            air_time += 1
        end
    else
        -- Otherwise, check if the new position will place the path back on the ground
        -- If it will then set the air time back to 0
        if CheckIfOnGround() then
            air_time = 0
        -- Otherwise, increase the air time and check if the position is below the previous point
        else
            air_time += 1
        end
    end

    -- If the new position is going up and is going higher than the agent can reasonably go, don't let the algrithm create a point there
    if jumped_from_location then
        if position.Y-jumped_from_location.Y > path_configurations.agents.max_jump_height then
            return false, air_time
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
            originPosition + Vector3.new(path_configurations.path_node_size, 0, 0),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, 0),
            originPosition + Vector3.new(0, path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(0, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, path_configurations.path_node_size, 0),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(-path_configurations.path_node_size, path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, path_configurations.path_node_size),
        }
    
        return newPositionsTable
    else
        local newPositionsTable = {
            originPosition + Vector3.new(path_configurations.path_node_size, 0, 0),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, 0),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(0, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, 0),
            originPosition + Vector3.new(0, -path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, 0, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, 0, path_configurations.path_node_size),
            originPosition + Vector3.new(path_configurations.path_node_size, -path_configurations.path_node_size, -path_configurations.path_node_size),
            originPosition + Vector3.new(-path_configurations.path_node_size, -path_configurations.path_node_size, path_configurations.path_node_size),
        }

        return newPositionsTable
    end
end

function Algrithm(startPosition: Vector3, endPosition: Vector3) : {waypoint}?
    local reached_destination : boolean = false
    local start_time : number = tick()
    local refresh_delay = tick()

    local checked_locations : {Vector3} = {startPosition, endPosition}
    local next_nodes_to_check : {node_information}  = {}
    local node_index : {node_information} = {}
    local key_nodes : {node_information} = {}

    -- Tell the script that the path is being generated (in-case manual interrupt)
    path_generating = true

    -- Create a connection to update the UI every so often
    local uiUpdate = runService.Heartbeat:Connect(function()
        if tick()-refresh_delay >= visualisation_configurations.refresh_delay then
            refresh_delay = tick()

            visualisation_configurations.nodesCheckedGUIPath.Text = visualisation_configurations.nodes_checked_text .. "\n" .. table.maxn(checked_locations)
        end
    end)

    -- Used in ValidateLocation()
    local isInPartParams = OverlapParams.new()
    isInPartParams.RespectCanCollide = true
    isInPartParams.FilterDescendantsInstances = {startPositionIndicator, endPositionIndicator}
    isInPartParams.FilterType = Enum.RaycastFilterType.Exclude

    local landedCheckParams = OverlapParams.new()
    landedCheckParams.RespectCanCollide = true
    landedCheckParams.FilterDescendantsInstances = {startPositionIndicator, endPositionIndicator}
    landedCheckParams.FilterType = Enum.RaycastFilterType.Exclude

    for _, player in pairs(game:GetService("Players"):GetPlayers()) do
        isInPartParams:AddToFilter(player.Character)
        landedCheckParams:AddToFilter(player.Character)
    end

    local node_number = 0

    table.insert(node_index, {node_number = node_number, properties = {position = startPosition, color = Color3.new(1.000000, 0.086275, 0.952941), material = Enum.Material.Neon}, attributes = {air_time = 0, distance = 0, on_ground = false, key_node = true}})
    table.insert(next_nodes_to_check, node_index[1])
    table.insert(key_nodes, node_index[1])

    while reached_destination == false do
        -- Sort the table so that the closest parts are chosen first
        if (node_number % 5 == 0) or (node_number <= 500) then
            table.sort(next_nodes_to_check, function(node_one : node_information, node_two : node_information)
                if (node_one.properties.position-endPosition).Magnitude < (node_two.properties.position-endPosition).Magnitude then
                    return true
                end

                return false
            end)
        end

        task.desynchronize()

        local next_node : node_information = next_nodes_to_check[1]

        local can_jump = false

        if next_node == nil then
            break
        end

        if path_interrupt == true then
            break
        end

        if next_node.attributes.on_ground == true then
            can_jump = true
        else
            if next_node.attributes.air_time <= (math.floor(path_configurations.agents.max_jump_height/path_configurations.path_node_size)-1) then
                can_jump = true
            end
        end
        
        for _, position : Vector3 in pairs(NextPositions(next_node.properties.position, can_jump)) do
            local new_node : node_information = {
                node_number = node_number + 1,
                properties = {
                    position = position,
                    color = archetypes.nodeArchetype.Color,
                    material = archetypes.nodeArchetype.Material
                },
                attributes = {
                    air_time = 0,
                    distance = (position-startPosition).Magnitude,
                    on_ground = false,
                    key_node = false,
                    jump_location = nil
                }
            }

            -- Check if the position is close enough to the end goal for it to count as reaching it
            if (position-endPosition).Magnitude <= path_configurations.success_within_stud_range then
                reached_destination = true
                break
            end

            local viableLocation = ValidateLocation(position, isInPartParams, checked_locations)

            if viableLocation == false then
                continue
            end

            local success, air_time = CheckPathLimits(position, next_node, landedCheckParams)

            if success == false then
                continue
            end

            new_node.attributes.air_time = air_time
            
            if air_time > 0 then
                new_node.attributes.on_ground = false

                if new_node.attributes.jump_location == nil then
                    new_node.attributes.jump_location = next_node.properties.position
                else
                    new_node.attributes.jump_location = next_node.attributes.jump_location
                end
            else
                new_node.properties.color = Color3.new(1, 0, 0)
                new_node.properties.material = Enum.Material.Neon
            end

            node_number += 1

            if node_number % path_configurations.key_node_rate == 0 then
                new_node.attributes.key_node = true
                new_node.properties.color = Color3.new(1.000000, 0.086275, 0.952941)
                new_node.properties.material = Enum.Material.Neon

                table.insert(key_nodes, new_node)
            end

            table.insert(next_nodes_to_check, new_node)
            table.insert(node_index, new_node)

            if node_number % (tick_delay) == 0 then
                task.synchronize()
                runService.Heartbeat:Wait()
                task.desynchronize()
            end
        end

        table.remove(next_nodes_to_check, 1)
        
        task.synchronize()
    end

    uiUpdate:Disconnect()

    table.insert(key_nodes, node_index[node_number])

    if log_level >= 1 then
        print("Reached end point in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end

    NodeVisualiser(node_index)

    if reached_destination == false then
        if path_interrupt == true then
            print("Path generation manually interrupted")
        else
            warn("Ran out of viable parts")
        end
        
        path_generating = false
        path_interrupt = false

        return
    end

    return PathCalculation(startPosition, endPosition, node_index, key_nodes)
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
        if i % (tick_delay*100) == 0 then
            runService.Heartbeat:Wait()
        end
    end

    if path_generating == true then
        path_interrupt = true
    end

    while path_interrupt == true do
        task.wait()
    end

    visualisation_configurations.progressGUIPath.ProgressBar.Bar.Position = UDim2.new(-1, 0, 0,0 )
    visualisation_configurations.progressGUIPath.ProgressInformation.Text = visualisation_configurations.node_creation_text .. "\n0/0 (100%)"
    visualisation_configurations.calculationPhaseGUIPath.Text = visualisation_configurations.calculation_phase_text .. "\nNot calculating"
    visualisation_configurations.nodesCheckedGUIPath.Text = visualisation_configurations.nodes_checked_text .. "\n0"

    local start_time = tick()
    local start_position = replicated_storage_objects.StartPosition.Value
    local end_position = replicated_storage_objects.EndPosition.Value

    if log_level >= 1 then
        print("Starting path creation")
    end

    startPositionIndicator.Position = start_position
    endPositionIndicator.Position = end_position

    local waypoints : {waypoint}? = Algrithm(start_position, end_position)

    if log_level >= 1 then
        print("Finished creating path in " .. math.round((tick()-start_time)*1000)/1000 .. "s")
    end

    if waypoints then
        TrialPath(waypoints)
    end
end

replicated_storage_objects.Regenerate.Event:Connect(StartSequence)

game:GetService("Players").LocalPlayer.CharacterAdded:Wait()

-- replicated_storage_objects.Regenerate:Fire()