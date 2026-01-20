-- @description numbers2notes_form
-- @version 1.0.5
-- @author Rock Kennedy
-- @about
--   # numbers2notes_form
--   Numbers2Notes Support File.
-- @changelog
--   + Removed indexing
--   + Updated version for forced update


local form = {

    sections_colors = { 
        ["Chorus"] = {156,55,50},
        ["Drop"] = {50,157,180},
        ["Ramp"] = {129,80,150}, 
        ["Pre-Chorus"] = {129,80, 50}, 
        ["Intro"] = {60,119,78}, 
        ["Solo"] = {0,98,109}, 
        ["Bridge"] = {75,136,154}, 
        ["Middle 8"] = {15,0,151}, 
        ["Verse"] = {63,83,137}, 
        ["Outro"] = {207,139,48}, 
        ["Fadeout"] = {0,0,0},
        ["else"] = {133,133,133}
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
        
        local verbose = true
        local vr = ""
        local errormessage = ""
        local G_original_user_entry = user_progression_entry
        local G_form_table = nil
        local G_section_table = {}

        -- __________________________________________  Find The Form and enter Each Section into a Table
        local function form_to_table(header_entry)
            header_entry = header_entry .. string.char(10)
            local form_table = {}
            local _, form_endchar = string.find(header_entry, "Form:")
            
            if form_endchar == nil then
                -- Form not found
            else
                local return_char_location, _ = string.find((string.sub(header_entry, form_endchar,-1)), string.char(10))
                if return_char_location == nil then
                    -- Missing return char
                else
                    local the_form = string.char(10) .. string.sub(header_entry, form_endchar +1, form_endchar + return_char_location -2)
                    local quote_active = false
                    local the_quote = ""
                    form_table = {}
                    for i = 1,string.len(the_form), 1 do
                        if string.sub(the_form, i, i) ~= " " and string.sub(the_form, i, i) ~= '"' and string.sub(the_form, i, i) ~= ',' and string.sub(the_form, i, i) ~= string.char(10) and quote_active == false then
                            table.insert(form_table, string.sub(the_form, i, i))
                        elseif string.sub(the_form, i, i) == '"' and quote_active == false then
                            quote_active = true
                        elseif string.sub(the_form, i, i) == '"' and quote_active == true then
                            quote_active = false
                            table.insert(form_table, the_quote)
                            the_quote = ""
                        elseif quote_active == true then
                            the_quote = the_quote .. string.sub(the_form, i, i)
                        else
                        end
                    end
                    if quote_active == true then
                        errormessage = errormessage .. "Section quote never closed" .. string.char(10)
                    end
                end
            end
            return form_table
        end

        -- __________________________________________  Group off all the data in sections
        local function sections_to_table(user_progression_entry)
            local section_table = {}
            local all_sections_data = user_progression_entry
            if verbose == true then errormessage = errormessage .. "--------------" .. all_sections_data ..  "--------------" .. string.char(10) end
            
            local brace_count = 0
            local brace_char_location, _ = string.find(all_sections_data, "{")
            
            if brace_char_location ~= nil then
                if verbose == true then errormessage = errormessage .. 'Found { at ' .. brace_char_location .. string.char(10) end
                local in_section = false
                local in_tag = false
                local in_custom = false
                local section_count = 0
                local tag = ""
                local current_section = ""
                local custom_tag = ""

                for i = brace_char_location, string.len(all_sections_data), 1 do
                    -- if verbose == true then errormessage = errormessage .. 'i = ' .. i .. ' cur char = ' .. string.sub(all_sections_data, i, i) .. string.char(10) end
                    if string.sub(all_sections_data, i, i) == "{" and in_tag == true then
                        if verbose == true then errormessage = errormessage .. "New section opened before old section closed" .. string.char(10) end
                    elseif string.sub(all_sections_data, i, i) == "{" and in_tag == false and section_count == 0 then
                        if verbose == true then errormessage = errormessage .. "First Run starting in tag" .. string.char(10) end
                        tag = ""
                        current_section = ""
                        in_tag = true
                        in_section = false
                        section_count = 1
                    elseif string.sub(all_sections_data, i, i) == "{" and in_tag == false and section_count > 0 and in_section == false then
                        if verbose == true then errormessage = errormessage .. "Started tag when not in session" .. string.char(10) end
                    elseif string.sub(all_sections_data, i, i) == "{" and in_tag == false and section_count > 0 and in_section == true then
                        if verbose == true then errormessage = errormessage .. "Opening the new, but first closing off" .. current_section ..string.char(10) end
                        section_table[tag] = current_section
                        if verbose == true then errormessage = errormessage .. "Table Item #" .. section_count .. " = " .. section_table[tag] .. string.char(10) end
                        tag = ""
                        current_section = ""
                        in_tag = true
                        in_section = false
                        section_count = section_count + 1
                    elseif string.sub(all_sections_data, i, i) == '"' and in_tag == true and in_custom == false then
                        custom_tag = string.sub(all_sections_data, i, i)
                        in_custom = true
                    elseif string.sub(all_sections_data, i, i) == '"' and in_tag == true and in_custom == true then
                        custom_tag =  custom_tag .. string.sub(all_sections_data, i, i)
                        in_custom = false
                        tag = custom_tag
                        custom_tag = ""
                    elseif string.sub(all_sections_data, i, i) == '"' and in_tag == false then
                        if verbose == true then errormessage = errormessage .. "Programmer note - Not in Tag" .. string.char(10) end
                    elseif string.sub(all_sections_data, i, i) == "}" and in_tag == false then
                        errormessage = errormessage .. i .. " ERROR Found a close section tag when not in a tag" .. string.char(10)
                        custom_tag = ""
                        tag = ""
                    elseif string.sub(all_sections_data, i, i) == "}" and in_tag == true then
                        if verbose == true then errormessage = errormessage .. i .. " Found a close section tag. Tag = " .. tag .. string.char(10) end
                        in_tag = false
                        in_section = true
                        custom_tag = ""
                    elseif in_section == false and in_tag == true then
                        tag = tag .. string.sub(all_sections_data, i, i)
                        if verbose == true then errormessage = errormessage .. i .. " Not In session | In tag = " .. tag .. string.char(10) end
                    elseif in_section == false and in_tag == false then
                        if verbose == true then errormessage = errormessage .. i .. " Not in session | Not in tag | Error?" .. string.char(10) end
                    elseif in_section == true and in_tag == true then
                        if verbose == true then errormessage = errormessage .. i .. " In session | In tag | Error?" .. tag .. string.char(10) end
                    elseif in_section == true and in_tag == false then
                        current_section = current_section .. string.sub(all_sections_data, i, i)
                        if verbose == true then errormessage = errormessage .. i .. " In session | Not In tag | Section = " .. current_section .. string.char(10) end
                    elseif in_tag == true and in_custom == true then            
                        custom_tag = custom_tag .. string.sub(all_sections_data, i, i)
                    elseif in_tag == true and in_custom == false then               
                        tag = tag .. string.sub(all_sections_data, i, i)
                    else
                        errormessage = errormessage .. i .. " Something went strangely wrong..." .. string.char(10)
                    end
                end
                
                if in_tag == false and section_count > 0 and in_section == true then
                    if verbose == true then errormessage = errormessage .. "Closing off final section" .. current_section ..string.char(10) end
                    section_table[tag] = current_section
                    if verbose == true then errormessage = errormessage .. "Table Item #" .. section_count .. " = " .. section_table[tag] .. string.char(10) end
                    tag = ""
                    current_section = ""
                    in_tag = true
                    in_section = false
                    section_count = section_count + 1           
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
        local replace_name = ""

        if G_form_table[1] == nil then
            errormessage = errormessage .. string.char(10) .. "There is no defined form." .. string.char(10)
            updated_text_to_process = G_original_user_entry
        end
        if G_section_table == nil then
            errormessage = errormessage .. string.char(10) .. "There are no defined sections." .. string.char(10)
            updated_text_to_process = G_original_user_entry
        end
        if  G_form_table[1] ~= nil and G_section_table ~= nil then
            errormessage = errormessage .. string.char(10) .. "Form defined and sections found..." .. string.char(10)
            for i, v in pairs(G_form_table) do 
                if verbose == true then errormessage = errormessage .. "Section Tag" .. i .. " = " .. v .. string.char(10) end
            end     
            for i, v in pairs(G_section_table) do 
                if verbose == true then errormessage = errormessage .. "Section " .. i .. " = " .. v .. string.char(10) end
            end
            updated_text_to_process = ""
            replace_name = ""
            for i, v in pairs(G_form_table) do
                replace_name = v
                errormessage = errormessage .. "DANG!!! " .. i .. " = " .. v .. string.char(10)
                if G_section_table[v] ~= nil then
                    if G_section_replacement_table[v] ~= nil then
                        replace_name = G_section_replacement_table[v]
                        updated_text_to_process = updated_text_to_process .. "{$" .. replace_name .. "$}" .. string.char(10)
                        updated_text_to_process = updated_text_to_process .. G_section_table[v]
                    else
                        updated_text_to_process = updated_text_to_process .. "{$" .. v .. "$}" .. string.char(10)
                        updated_text_to_process = updated_text_to_process .. G_section_table[v]
                    end
                else
                    -- !!! FIXED SYNTAX ERROR HERE (Added the ..) !!!
                    errormessage = errormessage .. "Section " .. v .. " was not found " .. string.char(10)
                end
            end
            errormessage = errormessage .. updated_text_to_process .. string.char(10)
        end
        return updated_text_to_process, errormessage
    end
}

return form


