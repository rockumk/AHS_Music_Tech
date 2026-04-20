-- @description numbers2notes_form
-- @version 1.0.7
-- @author Rock Kennedy
-- @noindex
-- @about
--   # numbers2notes_form
--   Numbers2Notes Support File.
-- @changelog
--   + Added native brace { } parsing to Form line
--   + Added carriage return \r sanitization

local form = {

    sections_colors = { 
        ["Chorus"] = {255, 102, 102},      -- Red 
        ["Drop"] = {204, 77, 230},         -- 
        ["Ramp"] = {179, 102, 255},        -- Purple/Blue
        ["Pre-Chorus"] = {179, 102, 255},  -- Purple/Blue
        ["Intro"] = {51, 255, 255},        -- Cyan
        ["Solo"] = {36, 159, 40},          -- Green
        ["Bridge"] = {255, 230, 51},       -- Yellow/Orange
        ["Middle 8"] = {204, 77, 230},     -- Magenta
        ["Verse"] = {102, 153, 255},       -- Blue
        ["Outro"] = {128, 204, 179},       -- Teal/Green
        ["Fadeout"] = {30, 30, 30},        -- Dark Gray
        ["else"] = {133, 133, 133}         -- Medium Gray
    },

    process_the_form = function(user_header_entry, user_progression_entry)

        local G_section_replacement_table = {
            ["#"] = "Count In",
            ["B"] = "Bridge",
            ["C"] = "Chorus",
            ["D"] = "Drop",
            ["F"] = "Fadeout",
            ["I"] = "Intro",
            ["M"] = "Middle 8",
            ["O"] = "Outro",
            ["P"] = "Pre-Chorus",
            ["R"] = "Ramp",
            ["S"] = "Solo",
            ["V"] = "Verse"
        }
        
        local verbose = false
        local errormessage = ""
        local G_original_user_entry = user_progression_entry
        local G_form_table = nil
        local G_section_table = {}

        -- __________________________________________  Find The Form and enter Each Section into a Table
        local function form_to_table(header_entry)
            local form_table = {}
            -- Sanitize invisible carriage returns from Windows!
            header_entry = header_entry:gsub("\r", "") .. "\n"
            
            local form_start = string.find(header_entry, "Form:")
            if not form_start then return form_table end
            
            local return_char = string.find(header_entry, "\n", form_start)
            if not return_char then return form_table end
            
            local the_form = string.sub(header_entry, form_start + 5, return_char - 1)
            
            local tokens = {}
            local current_token = ""
            local in_quotes = false
            local in_braces = false
            
            -- Read left to right, protecting "Quotes" and {Braces} natively!
            for i = 1, #the_form do
                local char = the_form:sub(i, i)
                if char == '"' and not in_braces then
                    in_quotes = not in_quotes
                elseif char == '{' and not in_quotes then
                    in_braces = true
                elseif char == '}' and not in_quotes then
                    in_braces = false
                    if current_token ~= "" then
                        table.insert(tokens, current_token)
                        current_token = ""
                    end
                elseif char == ' ' and not in_quotes and not in_braces then
                    if current_token ~= "" then
                        table.insert(tokens, current_token)
                        current_token = ""
                    end
                else
                    current_token = current_token .. char
                end
            end
            if current_token ~= "" then table.insert(tokens, current_token) end
            
            return tokens
        end

        -- __________________________________________  Group off all the data in sections
        local function sections_to_table(all_sections_data)
            local section_table = {}
            local brace_char_location = string.find(all_sections_data, "{")
            
            if brace_char_location ~= nil then
                local in_section = false
                local in_tag = false
                local in_custom = false
                local section_count = 0
                local tag = ""
                local current_section = ""
                local custom_tag = ""

                for i = brace_char_location, string.len(all_sections_data), 1 do
                    local char = string.sub(all_sections_data, i, i)
                    
                    if char == "{" and in_tag == false and section_count == 0 then
                        tag = ""
                        current_section = ""
                        in_tag = true
                        in_section = false
                        section_count = 1
                    elseif char == "{" and in_tag == false and section_count > 0 and in_section == true then
                        section_table[tag] = current_section
                        tag = ""
                        current_section = ""
                        in_tag = true
                        in_section = false
                        section_count = section_count + 1
                    elseif char == '"' and in_tag == true and in_custom == false then
                        custom_tag = char
                        in_custom = true
                    elseif char == '"' and in_tag == true and in_custom == true then
                        custom_tag = custom_tag .. char
                        in_custom = false
                        tag = custom_tag
                        custom_tag = ""
                    elseif char == "}" and in_tag == true then
                        in_tag = false
                        in_section = true
                        custom_tag = ""
                    elseif in_section == false and in_tag == true then
                        tag = tag .. char
                    elseif in_section == true and in_tag == false then
                        current_section = current_section .. char
                    elseif in_tag == true and in_custom == true then            
                        custom_tag = custom_tag .. char
                    end
                end
                
                if in_tag == false and section_count > 0 and in_section == true then
                    section_table[tag] = current_section
                end
            else
                section_table = nil
            end
            return section_table    
        end
        
        -- __________________________________________  Main
        G_form_table = form_to_table(user_header_entry)
        G_section_table = sections_to_table(G_original_user_entry)
        
        local updated_text_to_process = ""

        if not G_form_table or #G_form_table == 0 then
            errormessage = errormessage .. "\nThere is no defined form.\n"
            return G_original_user_entry, errormessage
        end
        if not G_section_table then
            errormessage = errormessage .. "\nThere are no defined sections.\n"
            return G_original_user_entry, errormessage
        end

        for i, v in ipairs(G_form_table) do
            if G_section_table[v] ~= nil then
                if G_section_replacement_table[v] ~= nil then
                    local replace_name = G_section_replacement_table[v]
                    updated_text_to_process = updated_text_to_process .. "{$" .. replace_name .. "$}\n"
                    updated_text_to_process = updated_text_to_process .. G_section_table[v]
                else
                    -- For C2, V2, Flute Duet, etc.
                    updated_text_to_process = updated_text_to_process .. "{$" .. v .. "$}\n"
                    updated_text_to_process = updated_text_to_process .. G_section_table[v]
                end
            else
                errormessage = errormessage .. "Section {" .. v .. "} was found in the Form but missing in the Chart!\n"
            end
        end
        
        return updated_text_to_process, errormessage
    end
}
return form
