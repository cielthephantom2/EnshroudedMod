local MOD_NAME = "Wisp Light Tuning"

local CONFIG = {
    consume_light_intensity = 24.0,
    consume_light_radius = 18.0,
    buff_light_intensity = 300,
    buff_light_radius = 100.0,
}

local TARGETS = {
    consume_vfx = "2ff99e47-bd76-4ea6-a0e7-f1824c434524",
    consume_sequence = "bc2f9d5f-806a-4c72-bb86-3d0e0e55e7e0",
    buff_type = "bcb33610-1afa-4316-9f18-e9db3f1d5ce6",
    buff_vfx = "550d4309-6cec-434b-8621-d3ce402e02f5",
}

local function safe_len(value)
    local ok, result = pcall(function()
        return #value
    end)

    if ok and type(result) == "number" then
        return result
    end

    return 0
end

local function try_get_field(value, field_name)
    local ok, result = pcall(function()
        return value[field_name]
    end)

    if ok then
        return result
    end

    return nil
end

local function get_variant_type(value)
    return try_get_field(value, "$type")
        or try_get_field(value, "type")
        or typeof(value)
end

local function get_variant_value(value)
    local wrapped_value = try_get_field(value, "$value")
    if wrapped_value ~= nil then
        return wrapped_value
    end

    wrapped_value = try_get_field(value, "value")
    if wrapped_value ~= nil then
        return wrapped_value
    end

    return value
end

local function normalize_string(value)
    local resolved = get_variant_value(value)
    if type(resolved) == "string" then
        return resolved
    end

    if resolved == nil then
        return nil
    end

    local ok, text = pcall(function()
        return tostring(resolved)
    end)

    if not ok or type(text) ~= "string" then
        return nil
    end

    if text == "nil" or text:match("^table:") or text:match("^userdata:") then
        return nil
    end

    return text
end

local function normalize_guid(value)
    local text = normalize_string(value)
    if not text then
        return nil
    end

    text = text:lower():gsub("[{}]", "")
    local guid = text:match("%x%x%x%x%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%-%x%x%x%x%x%x%x%x%x%x%x%x")
    return guid or text
end

local function get_resource_guid(resource)
    local data = resource and resource.data

    return normalize_guid(try_get_field(data, "$guid"))
        or normalize_guid(try_get_field(data, "guid"))
        or normalize_guid(try_get_field(data, "resourceId"))
        or normalize_guid(try_get_field(resource, "$guid"))
        or normalize_guid(try_get_field(resource, "guid"))
end

local function float_to_u32(value)
    if type(value) ~= "number" then
        return nil
    end

    if value == 0 then
        return 0
    end

    local sign = 0
    if value < 0 then
        sign = 1
        value = -value
    end

    local mantissa, exponent = math.frexp(value)
    exponent = exponent - 1
    mantissa = mantissa * 2 - 1

    local exponent_bits = exponent + 127
    if exponent_bits <= 0 then
        return 0
    end

    local mantissa_bits = math.floor(mantissa * 8388608 + 0.5)
    if mantissa_bits >= 8388608 then
        mantissa_bits = 0
        exponent_bits = exponent_bits + 1
    end

    return sign * 2147483648 + exponent_bits * 8388608 + mantissa_bits
end

local function encode_parameter_value(value)
    if type(value) == "boolean" then
        return value and 1 or 0
    end

    if type(value) == "number" then
        return float_to_u32(value)
    end

    return nil
end

local function build_parameter_index(vfx_data)
    local parameters = vfx_data and vfx_data.parameters
    local index = {}
    local parameter_count = safe_len(parameters)

    for parameter_index = 1, parameter_count do
        local parameter = parameters[parameter_index]
        local name = parameter and parameter.name
        local offset = parameter and parameter.offset
        if type(name) == "string" and type(offset) == "number" then
            index[name] = math.floor(offset / 4) + 1
        end
    end

    return index
end

local function patch_parameter_block(label, data_array, parameter_index, desired_values)
    if not data_array or not parameter_index then
        return 0, {}
    end

    local changed = 0
    local missing = {}

    for parameter_name, desired_value in pairs(desired_values) do
        local slot = parameter_index[parameter_name]
        if slot then
            local encoded_value = encode_parameter_value(desired_value)
            if encoded_value ~= nil and data_array[slot] ~= encoded_value then
                data_array[slot] = encoded_value
                changed = changed + 1
            end
        else
            missing[#missing + 1] = parameter_name
        end
    end

    if changed > 0 then
        print(string.format("[%s] Patched %s (%d values)", MOD_NAME, label, changed))
    end

    return changed, missing
end

local function find_resource_by_guid(resources, target_guid)
    local resource_count = safe_len(resources)
    for resource_index = 1, resource_count do
        local resource = resources[resource_index]
        if get_resource_guid(resource) == target_guid then
            return resource
        end
    end

    return nil
end

local function patch_vfx_defaults(resource, desired_values)
    local data = resource and resource.data
    local parameter_index = build_parameter_index(data)
    local default_data = data and data.defaultData and data.defaultData.data
    return patch_parameter_block(get_resource_guid(resource) .. " defaultData", default_data, parameter_index, desired_values)
end

local function patch_consume_sequence(resource, parameter_index, desired_values)
    local data = resource and resource.data
    local sub_sequences = data and data.subSequences
    local sequence_count = safe_len(sub_sequences)
    local changed = 0

    for sequence_index = 1, sequence_count do
        local sub_sequence = sub_sequences[sequence_index]
        local events = sub_sequence and sub_sequence.events
        local event_count = safe_len(events)

        for event_index = 1, event_count do
            local event = events[event_index]
            local event_type = get_variant_type(event)
            local event_value = get_variant_value(event)

            if event_type == "keen::VfxNotifierEvent"
                and normalize_guid(event_value and event_value.vfx) == TARGETS.consume_vfx then
                local patched = patch_parameter_block(
                    "consume sequence override",
                    event_value.vfxParameters and event_value.vfxParameters.data,
                    parameter_index,
                    desired_values
                )
                changed = changed + patched
            end
        end
    end

    return changed
end

local function patch_buff_resource(resource, parameter_index, desired_values)
    local data = resource and resource.data
    local while_applied = data and data.whileApplied
    local entry_count = safe_len(while_applied)
    local changed = 0
    local missing_names = {}

    for entry_index = 1, entry_count do
        local entry = while_applied[entry_index]
        if normalize_guid(entry and entry.vfx) == TARGETS.buff_vfx then
            local patched, missing = patch_parameter_block(
                "buff whileApplied override",
                entry.parameters and entry.parameters.data,
                parameter_index,
                desired_values
            )
            changed = changed + patched
            for missing_index = 1, safe_len(missing) do
                missing_names[missing[missing_index]] = true
            end
        end
    end

    local missing_list = {}
    for missing_name, _ in pairs(missing_names) do
        missing_list[#missing_list + 1] = missing_name
    end

    return changed, missing_list
end

local function main()
    print(string.format("[%s] Initializing", MOD_NAME))

    local vfx_resources = game.assets.get_resources_by_type("keen::VfxResource")
    local actor_sequence_resources = game.assets.get_resources_by_type("keen::actor::ActorSequenceResource")
    local buff_resources = game.assets.get_resources_by_type("keen::BuffType")

    if safe_len(vfx_resources) == 0 or safe_len(actor_sequence_resources) == 0 or safe_len(buff_resources) == 0 then
        print(string.format("[%s] Error: required resource types were not found", MOD_NAME))
        return
    end

    local consume_vfx_resource = find_resource_by_guid(vfx_resources, TARGETS.consume_vfx)
    local buff_vfx_resource = find_resource_by_guid(vfx_resources, TARGETS.buff_vfx)
    local consume_sequence_resource = find_resource_by_guid(actor_sequence_resources, TARGETS.consume_sequence)
    local buff_resource = find_resource_by_guid(buff_resources, TARGETS.buff_type)

    if not consume_vfx_resource or not buff_vfx_resource or not consume_sequence_resource or not buff_resource then
        print(string.format("[%s] Error: one or more target resources were not found", MOD_NAME))
        return
    end

    local consume_values = {
        light_enabled = true,
        light_intensity = CONFIG.consume_light_intensity,
        light_radius = CONFIG.consume_light_radius,
    }

    local buff_values = {
        light_enabled = true,
        light_intensity = CONFIG.buff_light_intensity,
        light_radius = CONFIG.buff_light_radius,
    }

    local consume_parameter_index = build_parameter_index(consume_vfx_resource.data)
    local buff_parameter_index = build_parameter_index(buff_vfx_resource.data)

    local total_changes = 0

    local changed_consume_defaults = patch_vfx_defaults(consume_vfx_resource, consume_values)
    total_changes = total_changes + changed_consume_defaults

    local changed_buff_defaults, missing_buff_defaults = patch_vfx_defaults(buff_vfx_resource, buff_values)
    total_changes = total_changes + changed_buff_defaults

    local changed_sequence = patch_consume_sequence(consume_sequence_resource, consume_parameter_index, consume_values)
    total_changes = total_changes + changed_sequence

    local changed_buff_override, missing_buff_override = patch_buff_resource(buff_resource, buff_parameter_index, buff_values)
    total_changes = total_changes + changed_buff_override

    local missing_parameters = {}
    for missing_index = 1, safe_len(missing_buff_defaults) do
        missing_parameters[missing_buff_defaults[missing_index]] = true
    end
    for missing_index = 1, safe_len(missing_buff_override) do
        missing_parameters[missing_buff_override[missing_index]] = true
    end

    if missing_parameters.light_radius then
        print(string.format(
            "[%s] Buff light radius is not exposed by the sustained VFX resource, so only consume radius and sustained intensity were patched.",
            MOD_NAME
        ))
    end

    print(string.format("[%s] Done. total_changes=%d", MOD_NAME, total_changes))
end

main()
