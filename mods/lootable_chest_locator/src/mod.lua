local MOD_NAME = "Lootable Chest Locator"

local CONFIG = {
    chest_light_radius = 12.0,
    chest_light_intensity = 15000.0,
    chest_glow_color = 4278245375,
    chest_ambient_volume = 0.55,
    chest_ambient_max_distance = 300.0,
}

local TARGETS = {
    chest_glow_vfx = "b375a6d3-ae29-4165-97b7-54d053016c21",
    chest_ambient_sound = "70437180-f100-45f8-8b04-9bbe3761b762",
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

local function get_variant_type(value)
    return try_get_field(value, "$type")
        or try_get_field(value, "type")
        or typeof(value)
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
    if type(value) == "table" and type(value.raw_u32) == "number" then
        return value.raw_u32
    end

    if type(value) == "boolean" then
        return value and 1 or 0
    end

    if type(value) == "number" then
        return float_to_u32(value)
    end

    return nil
end

local function raw_u32(value)
    return {
        raw_u32 = value,
    }
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

local function patch_parameter_block(data_array, parameter_index, desired_values)
    if not data_array or not parameter_index then
        return 0
    end

    local changed = 0

    for parameter_name, desired_value in pairs(desired_values) do
        local slot = parameter_index[parameter_name]
        if slot then
            if type(desired_value) == "table" and type(desired_value.raw_u32) ~= "number" then
                local value_count = safe_len(desired_value)
                for value_index = 1, value_count do
                    local encoded_component = encode_parameter_value(desired_value[value_index])
                    local array_slot = slot + value_index - 1
                    if encoded_component ~= nil and data_array[array_slot] ~= encoded_component then
                        data_array[array_slot] = encoded_component
                        changed = changed + 1
                    end
                end
            else
                local encoded_value = encode_parameter_value(desired_value)
                if encoded_value ~= nil and data_array[slot] ~= encoded_value then
                    data_array[slot] = encoded_value
                    changed = changed + 1
                end
            end
        end
    end

    return changed
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

local function is_target_chest_name(name)
    if type(name) ~= "string" then
        return false
    end

    if name:sub(1, 10) ~= "LootChest_" then
        return false
    end

    if name:sub(1, 16) == "LootChest_CHEAT_" then
        return false
    end

    if name:sub(1, 17) == "LootChest_Weapon_"
        or name:sub(1, 16) == "LootChest_Armor_"
        or name:sub(1, 17) == "LootChest_Locked_" then
        return true
    end

    local normalized_name = name:lower()
    if normalized_name:find("random_silver", 1, true)
        or normalized_name:find("random_gold", 1, true) then
        return true
    end

    if normalized_name:find("cairn_sarcophagus_silver", 1, true)
        or normalized_name:find("cairn_sarcophagus_gold", 1, true) then
        return true
    end

    return false
end

local function is_lootable_chest_template(resource)
    local data = resource and resource.data
    return is_target_chest_name(data and data.name)
end

local function template_uses_vfx(resource, target_vfx_guid)
    local data = resource and resource.data
    local components = data and data.components
    local component_count = safe_len(components)

    for index = 1, component_count do
        local component = components[index]
        local component_type = component and get_variant_type(component)
        local component_value = component and get_variant_value(component)

        if component_type == "keen::ecs::VfxComponentResource"
            and normalize_guid(component_value and component_value.vfx) == target_vfx_guid then
            return true
        end
    end

    return false
end

local function patch_template_vfx_reference(resource, target_vfx_guid)
    if not is_lootable_chest_template(resource) then
        return false, false
    end

    local components = resource.data and resource.data.components
    local component_count = safe_len(components)
    local found_vfx_resource = false
    local changed = false

    for index = 1, component_count do
        local component = components[index]
        local component_type = component and get_variant_type(component)
        local component_value = component and get_variant_value(component)

        if component_type == "keen::ecs::VfxComponentResource" then
            found_vfx_resource = true

            if normalize_guid(component_value and component_value.vfx) ~= target_vfx_guid then
                component_value.vfx = target_vfx_guid
                changed = true
            end
        end
    end

    return found_vfx_resource, changed
end

local function patch_template_vfx_overrides(resource, target_vfx_guid, parameter_index, desired_values)
    if not is_lootable_chest_template(resource) or not template_uses_vfx(resource, target_vfx_guid) then
        return 0
    end

    local components = resource.data and resource.data.components
    local component_count = safe_len(components)
    local changed = 0

    for index = 1, component_count do
        local component = components[index]
        local component_type = component and get_variant_type(component)
        local component_value = component and get_variant_value(component)

        if component_type == "keen::ecs::VfxParametersTemplateComponent" then
            changed = changed + patch_parameter_block(
                component_value and component_value.parameters and component_value.parameters.data,
                parameter_index,
                desired_values
            )
        end
    end

    return changed
end

local function patch_vfx_defaults(resource, desired_values)
    local data = resource and resource.data
    local parameter_index = build_parameter_index(data)
    local default_data = data and data.defaultData and data.defaultData.data
    return patch_parameter_block(default_data, parameter_index, desired_values), parameter_index
end

local function patch_sound_container(resource)
    local data = resource and resource.data
    if not data then
        return 0
    end

    local changed = 0

    if type(data.volume) == "number" and data.volume ~= CONFIG.chest_ambient_volume then
        data.volume = CONFIG.chest_ambient_volume
        changed = changed + 1
    end

    if type(data.maxDistance) == "number" and data.maxDistance ~= CONFIG.chest_ambient_max_distance then
        data.maxDistance = CONFIG.chest_ambient_max_distance
        changed = changed + 1
    end

    return changed
end

local function main()
    print(string.format("[%s] Initializing", MOD_NAME))

    local template_type = "keen::ecs::TemplateResource"
    local sound_type = "keen::SoundContainerResource"
    local template_resources = game.assets.get_resources_by_type(template_type)
    local vfx_resources = game.assets.get_resources_by_type("keen::VfxResource")
    local sound_resources = game.assets.get_resources_by_type(sound_type)

    if safe_len(template_resources) == 0 or safe_len(vfx_resources) == 0 then
        print(string.format("[%s] Error: required template or VFX resources were not found", MOD_NAME))
        return
    end

    local chest_glow_vfx = find_resource_by_guid(vfx_resources, TARGETS.chest_glow_vfx)
    local chest_ambient_sound = find_resource_by_guid(sound_resources, TARGETS.chest_ambient_sound)

    if not chest_glow_vfx then
        print(string.format("[%s] Error: chest glow VFX resource was not found", MOD_NAME))
        return
    end

    local glow_values = {
        prop_chest_color_silver = raw_u32(CONFIG.chest_glow_color),
        prop_chest_is_golden = true,
        prop_chest_color_golden = raw_u32(CONFIG.chest_glow_color),
        light_radius = CONFIG.chest_light_radius,
        light_intensity = CONFIG.chest_light_intensity,
        spawnMultiplier = 26.0,
    }
    local glow_defaults_changed, glow_parameter_index = patch_vfx_defaults(chest_glow_vfx, glow_values)

    local patched_glow_templates = 0
    local patched_glow_refs = 0
    local templates_without_vfx_resource = 0
    local resource_count = safe_len(template_resources)

    for index = 1, resource_count do
        local resource = template_resources[index]

        local found_vfx_resource, changed_vfx_reference = patch_template_vfx_reference(resource, TARGETS.chest_glow_vfx)
        if not found_vfx_resource and is_lootable_chest_template(resource) then
            templates_without_vfx_resource = templates_without_vfx_resource + 1
        end

        if changed_vfx_reference then
            patched_glow_refs = patched_glow_refs + 1
        end

        if patch_template_vfx_overrides(resource, TARGETS.chest_glow_vfx, glow_parameter_index, glow_values) > 0 then
            patched_glow_templates = patched_glow_templates + 1
        end
    end

    local patched_sound_values = 0
    if chest_ambient_sound then
        patched_sound_values = patch_sound_container(chest_ambient_sound)
    end

    print(string.format(
        "[%s] Done. template_type=%s sound_type=%s glow_defaults=%d glow_refs=%d glow_templates=%d missing_vfx_resource=%d sound_values=%d",
        MOD_NAME,
        tostring(template_type),
        tostring(sound_type),
        glow_defaults_changed,
        patched_glow_refs,
        patched_glow_templates,
        templates_without_vfx_resource,
        patched_sound_values
    ))
end

local ok, err = pcall(main)
if not ok then
    print(string.format("[%s] Error: %s", MOD_NAME, tostring(err)))
end