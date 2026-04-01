-- [Mod Configuration]
-- `damage_scale` multiplies the skill's base AttackMod across all supported weapon variants.
-- `range_scale` multiplies the combat hitbox size used by the skill.
local SKILL_CONFIG = {
    crash_down = {
        damage_scale = 1.2,
        range_scale = 1.5,
    },
    whirlwind_crescendo = {
        damage_scale = 1.2,
        range_scale = 1.5,
    },
    evasion_attack = {
        damage_scale = 1.2,
        range_scale = 1.5,
    },
}

local MOD_NAME = "Skill Attack Tuning"
local ATTACK_MOD_CONFIG_GUID = "cf8556df-77d6-4c36-a4ae-be1f9488f9bd"

local TARGET_SEQUENCE_PREFIXES = {
    {
        label = "Crash Down",
        prefix = "Attack_Player_Melee_Special_JumpAttack_",
        config = SKILL_CONFIG.crash_down,
    },
    {
        label = "Whirlwind Crescendo",
        prefix = "Attack_Player_Melee_Special_WhirlAttack_",
        config = SKILL_CONFIG.whirlwind_crescendo,
    },
    {
        label = "Evasion Attack",
        prefix = "Attack_Player_Melee_Special_DodgeAttack_",
        config = SKILL_CONFIG.evasion_attack,
    },
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

local function starts_with(value, prefix)
    return type(value) == "string" and value:sub(1, #prefix) == prefix
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

local function find_target_config(sequence_name)
    local prefix_count = safe_len(TARGET_SEQUENCE_PREFIXES)
    for index = 1, prefix_count do
        local entry = TARGET_SEQUENCE_PREFIXES[index]
        if starts_with(sequence_name, entry.prefix) then
            return entry
        end
    end

    return nil
end

local function find_attack_mod_entry(impact_values)
    local impact_value_count = safe_len(impact_values)
    for index = 1, impact_value_count do
        local impact_value = impact_values[index]
        local impact_value_type = impact_value and get_variant_type(impact_value)
        local impact_value_data = impact_value and get_variant_value(impact_value)
        if impact_value_data
            and impact_value_type == "keen::impact::FloatImpactConfig"
            and impact_value_data.configGuid == ATTACK_MOD_CONFIG_GUID then
            return impact_value_data
        end
    end

    return nil
end

local function scale_current_box_half_size(target_shape, scale)
    if not target_shape or not target_shape.halfSize then
        return false
    end

    local changed = false
    local axes = { "x", "y", "z" }
    for index = 1, 3 do
        local axis = axes[index]
        local current_value = target_shape.halfSize[axis]
        if type(current_value) == "number" then
            target_shape.halfSize[axis] = current_value * scale
            changed = true
        end
    end

    return changed
end

local function scale_current_sphere_radius(target_shape, scale)
    if not target_shape or type(target_shape.radius) ~= "number" then
        return false
    end

    target_shape.radius = target_shape.radius * scale
    return true
end

local function patch_collider_data(collider_data, range_scale)
    if range_scale == 1.0 or not collider_data then
        return false
    end

    local target_colliders = collider_data.dataArray
    local changed = false
    local collider_count = safe_len(target_colliders)
    for index = 1, collider_count do
        local target_collider = target_colliders[index]
        local target_value = target_collider and get_variant_value(target_collider)

        if target_value and target_value.shape then
            changed = scale_current_box_half_size(target_value.shape, range_scale) or changed
            changed = scale_current_sphere_radius(target_value.shape, range_scale) or changed
        end
    end

    return changed
end

local function patch_spawn_impact(event_value, config)
    if not event_value then
        return false
    end

    local changed = false
    local target_attack_mod = find_attack_mod_entry(event_value.impactValues)

    if target_attack_mod and type(config.damage_scale) == "number" and config.damage_scale ~= 1.0 then
        local new_value = target_attack_mod.value * config.damage_scale
        if target_attack_mod.value ~= new_value then
            target_attack_mod.value = new_value
            changed = true
        end
    end

    return patch_collider_data(event_value.colliderData, config.range_scale) or changed
end

local function patch_sub_sequence(sub_sequence, config)
    if not sub_sequence or not sub_sequence.events then
        return 0
    end

    local changed_events = 0
    local event_count = safe_len(sub_sequence.events)
    for index = 1, event_count do
        local event = sub_sequence.events[index]
        local event_type = event and get_variant_type(event)
        local event_value = event and get_variant_value(event)

        if event and event_type == "keen::actor::SpawnImpact" then
            if patch_spawn_impact(event_value, config) then
                changed_events = changed_events + 1
            end
        end
    end

    return changed_events
end

local function patch_resource(resource)
    local data = resource and resource.data
    if not data or not data.subSequences then
        return 0, 0
    end

    local patched_sequences = 0
    local patched_events = 0
    local sequence_count = safe_len(data.subSequences)

    for index = 1, sequence_count do
        local sub_sequence = data.subSequences[index]
        local target = find_target_config(sub_sequence and sub_sequence.name)

        if target then
            local changed_events = patch_sub_sequence(sub_sequence, target.config)
            if changed_events > 0 then
                patched_sequences = patched_sequences + 1
                patched_events = patched_events + changed_events
                print(string.format(
                    "[%s] Patched %s (%s): damage_scale=%.2f range_scale=%.2f events=%d",
                    MOD_NAME,
                    sub_sequence.name,
                    target.label,
                    target.config.damage_scale,
                    target.config.range_scale,
                    changed_events
                ))
            end
        end
    end

    return patched_sequences, patched_events
end

local function main()
    print(string.format("[%s] Initializing", MOD_NAME))

    local resources = game.assets.get_resources_by_type("keen::actor::ActorSequenceResource")
    if safe_len(resources) == 0 then
        print(string.format("[%s] Error: keen::actor::ActorSequenceResource not found", MOD_NAME))
        return
    end

    local total_sequences = 0
    local total_events = 0
    local resource_count = safe_len(resources)
    for index = 1, resource_count do
        local patched_sequences, patched_events = patch_resource(resources[index])
        total_sequences = total_sequences + patched_sequences
        total_events = total_events + patched_events
    end

    print(string.format(
        "[%s] Done. patched_sequences=%d patched_spawn_impacts=%d",
        MOD_NAME,
        total_sequences,
        total_events
    ))
end

local ok, err = pcall(main)
if not ok then
    print(string.format("[%s] Error: %s", MOD_NAME, tostring(err)))
end