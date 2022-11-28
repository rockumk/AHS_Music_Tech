-- @description Numbers2Notes
-- @version 1.0.1
-- @author Rock Kennedy
-- @about
--   # Numbers2Notes
--   Nashville Number System Style Chord Charting for Reaper.
-- @changelog
--   Name Change




-----------------------------------------------   REQUIRED FILES
local info = debug.getinfo(1, "S")
local script_path = info.source:match [[^@?(.*[\/])[^\/]-$]]
package.path = package.path .. ";" .. "?.lua"
local musictheory = require(script_path .. "numbers2notes_musictheory")
local spectrum = require(script_path .. "numbers2notes_spectrum")
local songs = require(script_path .. "numbers2notes_songs")
local help = require(script_path .. "numbers2notes_help")
local form = require(script_path .. "numbers2notes_form")


-----------------------------------------------   GUI VARIABLES AND SETUP

down_key_check = 0
last_element = 0
error_zone = ""
fade_up = true
transpar = .5
chosentheorychord = 1
chord_charting_area = ""
lead1_charting_area = ""
lead2_charting_area = ""
liveMIDI_playing_timer = 0
current_playing_tone_array = {}
last_play_root = 0
auidition_key_shift = 0
audition_track = nil
lyrics_charting_area = ""
notes_charting_area = ""
user_left_section_empty = false
the_OM_fail = ""
OM_ex_warning = ""
cancel_OM_opperation = false
OMfalsesofar = 0
the_itemOM = ""

header_area = [[Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: ]]

chord_charting_area = [[
{#}
- 

{I}




{V}	




{C}




{B}




{O}



]]


-----------------------------------------------   							GUI VARIABLES AND SETUP

render_feedback = ""
r = reaper
local ctx = r.ImGui_CreateContext("Numbers2Notes")
local main_viewport = r.ImGui_GetMainViewport(ctx)
local font = r.ImGui_CreateFont("Roboto Mono", 16)
r.ImGui_Attach(ctx, font)
local click_count, text = 0, ""
local centerx, centery = r.ImGui_Viewport_GetCenter(r.ImGui_GetMainViewport(ctx))
local window_flags = r.ImGui_WindowFlags_NoResize() | r.ImGui_WindowFlags_MenuBar() | r.ImGui_WindowFlags_NoCollapse()
r.ImGui_SetNextWindowSize(ctx, 1300, 700)
r.ImGui_SetNextWindowPos(ctx, 250, 150)
--r.ImGui_SetNextWindowPos(ctx, centerx, centery, r.ImGui_Cond_Appearing(), 0.5, 0.5)
r.ImGui_SetNextWindowCollapsed(ctx, false, nil)
r.ImGui_SetNextWindowBgAlpha(ctx, 1)



GridTrueFalse = true
ChordsTrueFalse = true
ChBassTrueFalse = true
Lead1TrueFalse = true
Lead2TrueFalse = true
BassTrueFalse = true
modal_on = false
show_headers = true
feedback_zone = "Use tabs above for more info and feedback."

--                                                                 IMGUI LINK FUNCTION

function Link(url)
    if not r.CF_ShellExecute then
        r.ImGui_Text(ctx, url)
        return
    end

    local color = r.ImGui_GetStyleColor(ctx, r.ImGui_Col_CheckMark())
    r.ImGui_TextColored(ctx, color, url)
    if r.ImGui_IsItemClicked(ctx) then
        r.CF_ShellExecute(url)
    elseif r.ImGui_IsItemHovered(ctx) then
        r.ImGui_SetMouseCursor(ctx, r.ImGui_MouseCursor_Hand())
    end
end


-----------------------------------------------   							IMGUI LOOP FUNCTION
function IM_GUI_Loop()
    local rv
    local rc
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_WindowBg(), 0xC8CED3FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBg(), 0xD5D5D5FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgActive(), 0xD5D5D5FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TitleBgCollapsed(), 0x63636382)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_MenuBarBg(), 0xD5D5D5FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Text(), 0x000000FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ChildBg(), 0xC8858500)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PopupBg(), 0x77B384F0)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_BorderShadow(), 0x466C9000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_FrameBg(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ScrollbarBg(), 0x82589E87)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Button(), 0x2A9AC0FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonHovered(), 0xFFF06FCC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_ButtonActive(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_Tab(), 0xEEEFEEDC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabHovered(), 0xFFFFFFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabActive(), 0xFFF06FCC)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TabUnfocused(), 0x834568F8)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableHeaderBg(), 0xC9BB00FF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_DockingEmptyBg(), 0x00F2FFFF)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableRowBg(), 0xFF000000)
    reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_TableBorderLight(), 0x0000FFFF)

    local visible, open =
        reaper.ImGui_Begin(ctx, "Numbers2Notes - Nashville Number Charts for Reaper", true, window_flags)

    r.ImGui_PushFont(ctx, font)

    if liveMIDI_playing_timer > 1 and liveMIDI_playing_timer < 41 then
        liveMIDI_playing_timer = liveMIDI_playing_timer - 1
    elseif liveMIDI_playing_timer < 0 then
        for i, v in pairs(current_playing_tone_array) do
            reaper.StuffMIDIMessage(0, 128, 48 + v + musictheory.root_table[play_root] + audition_key_shift, 100)
            reaper.StuffMIDIMessage(0, 128, 48 + v + musictheory.root_table[last_play_root] + audition_key_shift, 100)
        end
        liveMIDI_playing_timer = 0
    else
        for i, v in pairs(current_playing_tone_array) do
            reaper.StuffMIDIMessage(0, 128, 48 + v + musictheory.root_table[play_root] + audition_key_shift, 100)
            reaper.StuffMIDIMessage(0, 128, 48 + v + musictheory.root_table[last_play_root] + audition_key_shift, 100)
        end
        liveMIDI_playing_timer = 0
        reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 1)
    end

    if visible then
        if modal_on == true then
            r.ImGui_SetNextWindowPos(ctx, 800, 450)
            r.ImGui_OpenPopup(ctx, "Status:")
            if r.ImGui_BeginPopupModal(ctx, "Status:", nil, r.ImGui_WindowFlags_AlwaysAutoResize()) then
                r.ImGui_Text(ctx, "       Processing...       \n\n")
                r.ImGui_EndPopup(ctx)
            end
        end
        -- Always center this window when appearing

        reaper.ImGui_BeginGroup(ctx)
        if r.ImGui_BeginTabBar(ctx, "Charting", r.ImGui_TabBarFlags_None()) then
            if r.ImGui_BeginTabItem(ctx, "Chords") then
                charting_tab_mode = 1
                work_zone = chord_charting_area
                r.ImGui_EndTabItem(ctx)
            end
            --[[
			-- TABS
            if r.ImGui_BeginTabItem(ctx, "Lead 1") then
				charting_tab_mode = 2
				work_zone = lead1_charting_area
				r.ImGui_EndTabItem(ctx)
            end
			if r.ImGui_BeginTabItem(ctx, "Lead 2") then
				charting_tab_mode = 3
				work_zone = lead2_charting_area
				r.ImGui_EndTabItem(ctx)
			end					
			if r.ImGui_BeginTabItem(ctx, "Bass") then
				charting_tab_mode = 4
				work_zone = bass_charting_area
				r.ImGui_EndTabItem(ctx)	
            end 
			]]
            if r.ImGui_BeginTabItem(ctx, "Lyrics") then
                charting_tab_mode = 5
                work_zone = lyrics_charting_area
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Notes") then
                charting_tab_mode = 6
                work_zone = notes_charting_area
                r.ImGui_EndTabItem(ctx)
            end
            r.ImGui_EndTabBar(ctx)
        end

        if charting_tab_mode == 1 then
            if show_headers == true then
                if r.ImGui_Button(ctx, "Hide Header Info", nil, nil) then
                    show_headers = false
                end
                r.ImGui_SameLine(ctx)
                rv, header_area =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##header_area",
                    header_area,
                    541,
                    102,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
                rv, chord_charting_area =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##chord_charting_area",
                    chord_charting_area,
                    685,
                    487,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
            else
                if r.ImGui_Button(ctx, "Display Header Info", nil, nil) then
                    show_headers = true
                end
                rv, chord_charting_area =
                    r.ImGui_InputTextMultiline(
                    ctx,
                    "##chord_charting_area",
                    chord_charting_area,
                    685,
                    562,
                    reaper.ImGui_InputTextFlags_AllowTabInput()
                )
            end

            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Chart Tracks", nil, nil) then
                modal_on = true
                render_all()
            end
        elseif charting_tab_mode == 2 then
            rv, lead1_charting_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lead1_charting_area",
                lead1_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Lead 1 Track", nil, nil) then
                render_lead1()
            end
        elseif charting_tab_mode == 3 then
            rv, lead2_charting_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lead2_charting_area",
                lead2_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Lead 2 Track", nil, nil) then
                render_lead2()
            end
        elseif charting_tab_mode == 4 then
            rv, bass_charting_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##bass_charting_area",
                bass_charting_area,
                685,
                589,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            reaper.ImGui_Dummy(ctx, 250, 5)
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Render Bass Track", nil, nil) then
                render_bass()
            end
        elseif charting_tab_mode == 5 then
            rv, lyrics_charting_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##lyrics_charting_area",
                lyrics_charting_area,
                685,
                618,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        elseif charting_tab_mode == 6 then
            rv, notes_charting_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##notes_charting_area",
                notes_charting_area,
                685,
                618,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        reaper.ImGui_EndGroup(ctx)
        r.ImGui_SameLine(ctx)
        reaper.ImGui_BeginGroup(ctx)

        if r.ImGui_BeginMenuBar(ctx) then
            if r.ImGui_BeginMenu(ctx, "File") then
                if r.ImGui_MenuItem(ctx, "New Chart") then
                    header_area = [[Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: ]]
                    chord_charting_area = [[
{#}
- -

{I}




{V}	




{C}




{B}




{O}




]]
                end

                if r.ImGui_MenuItem(ctx, "Open Chart") then
				
				
					local info = debug.getinfo(1,'S')
					local path = info.source:match[[^@?(.*[\/])[^\/]-$]]
					local chordchart_path = path .. 'ChordCharts/'
				
                    retval, selected_path =
                        reaper.GetUserFileNameForRead(chordchart_path,
                        "Select the Chord Chart you wish to open.",
                        "txt"
                    )





                    --reaper.ShowConsoleMsg(path .. "\n")
                    local settings = io.open(selected_path, "r")
                    if settings ~= nil then
                        local readfilecontents = settings:read("*all")
						
						
						local textlocationtable = {header_startie, header_endie, chords_startie, chords_endie, lyrics_startie, lyrics_endie, notes_startie, notes_endie}
						
						for i,v in pairs(textlocationtable) do
						textlocationtable[i] = nil
						end
						

                        _, header_startie = string.find(readfilecontents, "<header_area>\n")
						header_endie, _  = string.find(readfilecontents, "\n</header_area>")
                        _, chords_startie = string.find(readfilecontents, "<chord_charting_area>\n")
						chords_endie, _  = string.find(readfilecontents, "\n</chord_charting_area>")	
                        --_, lead1_startie = string.find(readfilecontents, "<lead1_charting_area>\n")
						--lead1_endie, _  = string.find(readfilecontents, "\n</lead1_charting_area>")	
						--_, lead2_startie = string.find(readfilecontents, "<lead2_charting_area>\n")
						--lead2_endie, _  = string.find(readfilecontents, "\n</lead2_charting_area>")
                        --_, bass_startie = string.find(readfilecontents, "<bass_charting_area>\n")
						--bass_endie, _  = string.find(readfilecontents, "\n</bass_charting_area>")	
                        _, lyrics_startie = string.find(readfilecontents, "<lyrics_charting_area>\n")
						lyrics_endie, _  = string.find(readfilecontents, "\n</lyrics_charting_area>")	
                        _, notes_startie = string.find(readfilecontents, "<notes_charting_area>\n")
						notes_endie, _  = string.find(readfilecontents, "\n</notes_charting_area>")


						

						
						
						
						--chords_endie, lyrics_startie  = string.find(readfilecontents, "\n</chord_charting_area>\n<lyrics_charting_area>\n")
						--lyrics_endie, notes_startie  = string.find(readfilecontents, "\n</lyrics_charting_area>\n<notes_charting_area>\n")
						notes_endie, _  = string.find(readfilecontents, "\n</notes_charting_area>\n</Numbers2NotesProject>")
						

						if header_startie ~= nil and header_endie ~= nil and header_endie > header_startie then
                        header_area = string.sub(readfilecontents, header_startie + 1, header_endie - 1)
						end
						
						if chords_startie ~= nil and chords_endie ~= nil and chords_endie > chords_startie then						
                        chord_charting_area = string.sub(readfilecontents, chords_startie + 1, chords_endie - 1)			
						end

						--if lead1_startie ~= nil and lead1_endie ~= nil and lead1_endie > lead1_startie then						
                        --lead1_charting_area = string.sub(readfilecontents, lead1_startie + 1, lead1_endie - 1)
						--end

						if lyrics_startie ~= nil and lyrics_endie ~= nil and lyrics_endie > lyrics_startie then						
						lyrics_charting_area = string.sub(readfilecontents, lyrics_startie + 1, lyrics_endie - 1)
						end

						if notes_startie ~= nil and notes_endie ~= nil and notes_endie > notes_startie then						
						notes_charting_area = string.sub(readfilecontents, notes_startie + 1, notes_endie - 1)
						end
						
						
						
                    end
                end
                if r.ImGui_MenuItem(ctx, "Save") then -- MENU ITEMS

						Autosave()
                end
                if r.ImGui_MenuItem(ctx, "Save as...") then
						_, quit_title_startso  = string.find(header_area, "Title: ")			-- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
						quit_title_endso, _  = string.find(header_area, "Writer:")
						
						quittitlefound = string.sub(header_area, quit_title_startso+1, quit_title_endso-2)
						thetime = os.date('%Y-%m-%d %H-%M-%S')
						if string.len(quittitlefound) < 30 and quittitlefound ~= nil then

						filenamewillbe = quittitlefound .. " " .. thetime .. ".txt"
						else
						filenamewillbe = "N2Nautobackup " .. thetime .. ".txt"
						end
						
						local info = debug.getinfo(1,'S')
						local path = info.source:match[[^@?(.*[\/])[^\/]-$]]
						local chordchart_path = path .. 'ChordCharts/'
						retval, fileName =
							reaper.JS_Dialog_BrowseForSaveFile(
							"Save Chord Chart as...",
							chordchart_path,
							filenamewillbe,
							".txt"
						)

						write_path = io.open(filenamewillbe, "w")
						write_path:write("<Numbers2NotesProject>\n<header_area>\n"..header_area .."\n</header_area>\n<chord_charting_area>\n"..chord_charting_area.."\n</chord_charting_area>\n<lyrics_charting_area>\n"..lyrics_charting_area.."\n</lyrics_charting_area>\n<notes_charting_area>\n"..notes_charting_area.."\n</notes_charting_area>\n</Numbers2NotesProject>")
						write_path:close()	
                end
                --if r.ImGui_MenuItem(ctx, "Quit") then
                --r.ShowConsoleMsg("Quitting...\n")
                --end
                r.ImGui_EndMenu(ctx)
            end
            --[[if r.ImGui_BeginMenu(ctx, "Edit") then
                if r.ImGui_MenuItem(ctx, "Select All") then       			-- MENU ITEMS
                    r.ShowConsoleMsg("Selecting...\n")
                end
                if r.ImGui_MenuItem(ctx, "Cut") then
                    r.ShowConsoleMsg("Cutting...\n")
                end
                if r.ImGui_MenuItem(ctx, "Copy") then
                    r.ShowConsoleMsg("Copying...\n")
                end
                if r.ImGui_MenuItem(ctx, "Paste") then
                    r.ShowConsoleMsg("Pasting...\n")
                end
                r.ImGui_EndMenu(ctx)
            end
			]]
            --[[
            if r.ImGui_BeginMenu(ctx, "Formats") then						-- MENU ITEMS
                if r.ImGui_MenuItem(ctx, "Get Formats Info") then
                    r.ShowConsoleMsg("Open Format Info...\n")
                end
                if r.ImGui_MenuItem(ctx, "Get info on BIAB") then
                    r.ShowConsoleMsg("Showing BIAB info\n")
                end
                if r.ImGui_MenuItem(ctx, "Get info on OneMotion.com Chord Player") then
                    r.ShowConsoleMsg("Chord Player Info\n")
                end
                if r.ImGui_MenuItem(ctx, 'Convert Clipboard contents from to Onemotion.com "Edit All"') then
                    import_onemotion()
                end
                if r.ImGui_MenuItem(ctx, 'Export to Onemotion.com Chord Player "Edit All" paste in') then
                    render_onemotion()
                end
                if r.ImGui_MenuItem(ctx, "Get info on ChordSheet.com") then
                    r.ShowConsoleMsg("Chordsheet.com Info\n")
                end
                if r.ImGui_MenuItem(ctx, "Go to Chordsheet.com") then
                    r.ShowConsoleMsg("Open Chordsheet.com website\n")
                end
                r.ImGui_EndMenu(ctx)										-- MENU ITEMS
            end
            if r.ImGui_BeginMenu(ctx, "Audition and Render") then
                if r.ImGui_MenuItem(ctx, "Audition Selection") then
                    r.ShowConsoleMsg("Auditioning Selection\n")
                end
                if r.ImGui_MenuItem(ctx, "Audition Chart") then
                    r.ShowConsoleMsg("Auditioning Chart\n")
                end
                if r.ImGui_MenuItem(ctx, "Render Selection at Cursor") then
                    r.ShowConsoleMsg("Render Selection at Cursor\n")
                end
                if r.ImGui_MenuItem(ctx, "Render Chart at Cursor") then
                    r.ShowConsoleMsg("Render Chart at Cursor\n")
                end
                if r.ImGui_MenuItem(ctx, "Render New Chart Tracks") then
                    render_all()
                end															-- MENU ITEMS
                r.ImGui_EndMenu(ctx)
            end
			]]
            r.ImGui_EndMenuBar(ctx)
        end
        if r.ImGui_BeginTabBar(ctx, "Feedback", r.ImGui_TabBarFlags_None()) then
            if r.ImGui_BeginTabItem(ctx, "Render") then
                feedback_tab_mode = 0
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Entry") then
                feedback_tab_mode = 1
                r.ImGui_EndTabItem(ctx)
            end -- TABS																	-- TABS

            --[[
		 if r.ImGui_BeginTabItem(ctx, "Options") then
				feedback_tab_mode = 2
				r.ImGui_EndTabItem(ctx)
            end
			if r.ImGui_BeginTabItem(ctx, "Arrange") then
				feedback_tab_mode = 3
				r.ImGui_EndTabItem(ctx)
            end						
			]]
            if r.ImGui_BeginTabItem(ctx, "Import") then
                feedback_tab_mode = 4
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Export") then
                feedback_tab_mode = 5
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Theory") then
                feedback_tab_mode = 6
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Chains") then
                feedback_tab_mode = 7
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Help") then
                feedback_tab_mode = 8
                r.ImGui_EndTabItem(ctx)
            end
            if r.ImGui_BeginTabItem(ctx, "Beta Users") then
                feedback_tab_mode = 9
                r.ImGui_EndTabItem(ctx)
            end




            --[[			


			if onemotionimport ~= "" then
				feedback_zone = onemotionimport
				else
				feedback_zone = 'While at the OneMotion.com Chord Player go to "Edit all" and copy the contents.'
				end
				
				           -- if r.ImGui_BeginTabItem(ctx, "Chordsheet.com") then
            --    r.ImGui_EndTabItem(ctx)
			--	feedback_tab_mode = 5				
			--	feedback_zone = help.Chordsheet_output
            --end																-- TABS
			
							feedback_zone = help.Sample_song
			
								if onemotionimport ~= "" then
				feedback_zone = onemotionimport
				else
				feedback_zone = 'While at the OneMotion.com Chord Player go to "Edit all" and copy the contents.'
				end
				
								if onemotionoutput ~= "" then
				feedback_zone = onemotionoutput
				else
				feedback_zone = help.Onemotion_output
				end
				
				]]
            --if r.ImGui_BeginTabItem(ctx, "Help") then
            --feedback_tab_mode = 6
            --feedback_zone = help.Template
            --  r.ImGui_EndTabItem(ctx)
            --end
            -- if r.ImGui_BeginTabItem(ctx, "Code Help") then
            --    r.ImGui_EndTabItem(ctx)
            --	feedback_tab_mode = 8
            --	feedback_zone = help.Code_help
            -- end																-- TABS
            --  if r.ImGui_BeginTabItem(ctx, "Section Help") then
            --      r.ImGui_EndTabItem(ctx)
            --	feedback_tab_mode = 9
            --	feedback_zone = help.Section_help
            --  end
            --  if r.ImGui_BeginTabItem(ctx, "Chord Help") then
            --        r.ImGui_EndTabItem(ctx)
            --		feedback_tab_mode = 10
            --		feedback_zone = help.Chord_help
            --    end
            --    if r.ImGui_BeginTabItem(ctx, "Rhythm Help") then
            --         r.ImGui_EndTabItem(ctx)
            --		feedback_tab_mode = 11
            --		feedback_zone = help.Rhythm_help
            --     end
            --if r.ImGui_BeginTabItem(ctx, "Swing Help") then
            -- r.ImGui_EndTabItem(ctx)
            --end																-- TABS
            r.ImGui_EndTabBar(ctx)
        end
        if feedback_tab_mode == 4 then
            if r.ImGui_BeginTabBar(ctx, "Import", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Import Letter Chords") then
                    import_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                --[[]
				if r.ImGui_BeginTabItem(ctx, 'Import BIAB Chords') then
					import_tab_mode = 2
					r.ImGui_EndTabItem(ctx)
				end
				]]
                if r.ImGui_BeginTabItem(ctx, "Import OneMotion Chords") then
                    import_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end
                r.ImGui_EndTabBar(ctx)
            end
        end

        if feedback_tab_mode == 5 then
            if r.ImGui_BeginTabBar(ctx, "Export", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Export to BIAB") then
                    export_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Export to OneMotion.com") then
                    export_tab_mode = 2
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Export to Chordsheet.com") then
                    export_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end
                r.ImGui_EndTabBar(ctx)
            end
        end

        if feedback_tab_mode == 8 then
            if r.ImGui_BeginTabBar(ctx, "Help", r.ImGui_TabBarFlags_None()) then
                if r.ImGui_BeginTabItem(ctx, "Sample Song") then
                    help_tab_mode = 1
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Template") then
                    help_tab_mode = 2
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Code Help") then
                    help_tab_mode = 3
                    r.ImGui_EndTabItem(ctx)
                end -- TABS
                if r.ImGui_BeginTabItem(ctx, "Section Help") then
                    help_tab_mode = 4
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Chord Help") then
                    help_tab_mode = 5
                    r.ImGui_EndTabItem(ctx)
                end
                if r.ImGui_BeginTabItem(ctx, "Rhythm Help") then
                    help_tab_mode = 6
                    r.ImGui_EndTabItem(ctx)
                end
                --if r.ImGui_BeginTabItem(ctx, "Swing Help") then
                --		help_tab_mode = 7
                --   r.ImGui_EndTabItem(ctx)
                --end
                r.ImGui_EndTabBar(ctx)
            end
        end
        if feedback_tab_mode == 9 then
		
reaper.ImGui_Text(ctx, "REQUIRED PLUGINS FOR THE DEFAULT PROJECT")
reaper.ImGui_Text(ctx, "Numbers2Notes does not yet allow the user to select plugins.")
reaper.ImGui_Text(ctx, "The plugins below are required to fully set up the default configuration.")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "INCLUDED JSFX --------------------------------------------")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "- ReaPulse")
reaper.ImGui_Text(ctx, "- SwingTrackMIDI")
reaper.ImGui_Text(ctx, "- SwingProjectMIDI")
reaper.ImGui_Text(ctx, "- ReaCenterMIDIpitch")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "3RD PARTY JSFX --------------------------------------------")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "- pad-synth.jsfx ")
r.ImGui_SameLine(ctx)
Link("https://github.com/geraintluff/jsfx-pad-synth")
reaper.ImGui_Text(ctx, "   Or add the reapack... ")
r.ImGui_SameLine(ctx)
Link("https://geraintluff.github.io/jsfx/index.xml")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "3RD PARTY VST PLUGINS --------------------------------------------")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "- Dragonfly Room Reverb ")
r.ImGui_SameLine(ctx)
Link("https://github.com/michaelwillis/dragonfly-reverb/releases/tag/3.2.5")
reaper.ImGui_Text(ctx, "- STFU ")
r.ImGui_SameLine(ctx)
Link("https://www.kvraudio.com/product/stfu-by-zeek/downloads")
reaper.ImGui_Text(ctx, "- Tattoo ")
r.ImGui_SameLine(ctx)
Link("https://www.audiodamage.com/pages/free-and-legacy")
reaper.ImGui_Text(ctx, "- Merlittzer ")
r.ImGui_SameLine(ctx)
Link("https://plugins4free.com/plugin/2322/")
reaper.ImGui_Text(ctx, "- LibreARP ")
r.ImGui_SameLine(ctx)
Link("https://librearp.gitlab.io/download/")
reaper.ImGui_Text(ctx, "- Sitala ")
r.ImGui_SameLine(ctx)
Link("https://decomposer.de/sitala/")
reaper.ImGui_Text(ctx, "")
reaper.ImGui_Text(ctx, "AIRWINDOWS ")
r.ImGui_SameLine(ctx)
Link("https://www.airwindows.com/")
reaper.ImGui_Text(ctx, "- Calibre")
reaper.ImGui_Text(ctx, "- Isolator")
reaper.ImGui_Text(ctx, "- Holt")


		
		
		

					
					

        end











        if feedback_tab_mode == 0 then
            reaper.ImGui_Text(ctx, "Render Feedback:")
            r.ImGui_InputTextMultiline(
                ctx,
                "##feedback_zone",
                render_feedback,
                592,
                573,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        wx = 77
        hx = 19
        if feedback_tab_mode == 1 then
            --reaper.ImGui_Text(ctx, "Entry Buttons:")

            the_root_colors = {244, 244, 244}
            thecolor =
                reaper.ImGui_ColorConvertDouble4ToU32(
                the_root_colors[1] * (1.0 / 255.0),
                the_root_colors[2] * (1.0 / 255.0),
                the_root_colors[3] * (1.0 / 255.0),
                1
            )
					
			reaper.ImGui_BeginGroup(ctx)
			reaper.ImGui_Dummy(ctx, 3, 5)
            r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
            if r.ImGui_Button(ctx, "Rest", wx, hx) then
                chord_charting_area = chord_charting_area .. "-  "
            end
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Return", wx, hx) then
                chord_charting_area = chord_charting_area .. string.char(10)
            end

            r.ImGui_PopStyleColor(ctx, 1)
			reaper.ImGui_EndGroup(ctx)
            r.ImGui_SameLine(ctx)
            reaper.ImGui_Text(ctx, "Hold Shift for Flat Roots / Ctrl to place in chart.\nGlowing = Very Popular / Bright = In Diatonic Scale")

            --r.ImGui_Separator(ctx)

            for i, v in pairs(musictheory.button_table) do
                if v[1] == "L" then
                    reaper.ImGui_Text(ctx, v[2])
                    r.ImGui_SameLine(ctx)
                    r.ImGui_Separator(ctx)
                    down_key_check = reaper.ImGui_GetKeyMods(ctx)
                else
                    if transpar > .9 then
                        fade_up = false
                    elseif transpar < .4 then
                        fade_up = true
                    end
                    if fade_up == false then
                        transpar = transpar - .0007
                    elseif fade_up == true then
                        transpar = transpar + .0007
                    end

                    if down_key_check == 2 or down_key_check == 3 then
                        play_root = "1"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][1] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        flat_level = .59

                        play_root = "b2"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b3"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "4"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][4] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b5"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b6"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "b7"
                        the_root_colors = musictheory.root_colors[play_root]
                        thecolor =
                            reaper.ImGui_ColorConvertDouble4ToU32(
                            the_root_colors[1] * (1.0 / 255.0),
                            the_root_colors[2] * (1.0 / 255.0),
                            the_root_colors[3] * (1.0 / 255.0),
                            flat_level
                        )
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                    else
                        play_root = "1"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][1] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "2"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][2] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "3"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][3] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end

                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "4"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][4] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "5"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "       " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][5] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "6"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "m      " then
                            thecolor = reaper.ImGui_ColorConvertDouble4ToU32(1, 1, 1, transpar)
                        else
                            if v[3][6] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end
                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                        r.ImGui_SameLine(ctx)

                        play_root = "7"
                        the_root_colors = musictheory.root_colors[play_root]
                        if v[2] == "dim    " then
                            thecolor =
                                reaper.ImGui_ColorConvertDouble4ToU32(
                                the_root_colors[1] * (1.0 / 255.0),
                                the_root_colors[2] * (1.0 / 255.0),
                                the_root_colors[3] * (1.0 / 255.0),
                                1
                            )
                        else
                            if v[3][7] ~= nil then
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    1
                                )
                            else
                                thecolor =
                                    reaper.ImGui_ColorConvertDouble4ToU32(
                                    the_root_colors[1] * (1.0 / 255.0),
                                    the_root_colors[2] * (1.0 / 255.0),
                                    the_root_colors[3] * (1.0 / 255.0),
                                    .2
                                )
                            end
                        end

                        r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                        play_button_midi(v, play_root)
                        r.ImGui_PopStyleColor(ctx, 1)
                    end
                end
            end

            reaper.ImGui_InputTextFlags_AllowTabInput()
        end

        if feedback_tab_mode == 2 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")

        --[[
		--r.ImGui_InputTextMultiline(ctx,"##feedback_zone", render_feedback, 577, 520,reaper.ImGui_InputTextFlags_AllowTabInput())
				reaper.ImGui_BeginGroup(ctx)
		reaper.ImGui_Dummy(ctx, 3, 5)
        if not type(bol) then bol = true end								-- BUTTONS
        rc, GridTrueFalse = r.ImGui_Checkbox(ctx, "Render Full-Range Chord Grid", GridTrueFalse)
        if not type(bol) then bol = true end
		rc, ChordsTrueFalse = r.ImGui_Checkbox(ctx, "Render Chords", ChordsTrueFalse)
        if not type(bol) then bol = true end
        rc, ChBassTrueFalse = r.ImGui_Checkbox(ctx, "Render Chord + Bass Combo", ChBassTrueFalse)		
        if not type(bol) then bol = true end
		reaper.ImGui_EndGroup(ctx)
		r.ImGui_SameLine(ctx)
		reaper.ImGui_BeginGroup(ctx)
		reaper.ImGui_Dummy(ctx, 3, 5)	
		reaper.ImGui_EndGroup(ctx)
		r.ImGui_SameLine(ctx)
		reaper.ImGui_BeginGroup(ctx)
				reaper.ImGui_Dummy(ctx, 3, 5)
		if not type(bol) then bol = true end
        rc, Lead1TrueFalse = r.ImGui_Checkbox(ctx, "Render Lead 1", Lead1TrueFalse)
		if not type(bol) then bol = true end
        rc, Lead2TrueFalse = r.ImGui_Checkbox(ctx, "Render Lead 2", Lead2TrueFalse)
        if not type(bol) then bol = true end
        rc, BassTrueFalse = r.ImGui_Checkbox(ctx, "Render Bass", BassTrueFalse)

		reaper.ImGui_EndGroup(ctx)
		]]
        end
        if feedback_tab_mode == 3 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")
        end

        if feedback_tab_mode == 4 and import_tab_mode == 1 then
            reaper.ImGui_Text(
                ctx,
                'Paste or type in lettered chord names. See "Help:Rhythm Help" for\nrhythmic formatting.  Then convert to Numbers2Notes System.\n'
            )
            Link("https://en.wikipedia.org/wiki/Nashville_Number_System")
            rv, letter_import =
                r.ImGui_InputTextMultiline(
                ctx,
                "##letter_import",
                letter_import,
                592,
                239,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            rv, letter_to_num_key =
                r.ImGui_InputTextMultiline(
                ctx,
                "Key",
                letter_to_num_key,
                35,
                22,
                nil
            )
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Convert Letters >> Numbers2Notes format", nil, nil) then
                numbers_from_Letters = letters_to_numbers(letter_to_num_key, letter_import)
            end
            rv, numbers_from_Letters =
                r.ImGui_InputTextMultiline(
                ctx,
                "##numbers_from_Letters",
                numbers_from_Letters,
                592,
                242,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 4 and import_tab_mode == 2 then
            reaper.ImGui_Text(ctx, "Not yet implemented.")
        end

        if feedback_tab_mode == 4 and import_tab_mode == 3 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for importing from OneMotion.Com's \nChord Player.\n\n"
            )
            Link("https://www.onemotion.com/chord-player/")
            reaper.ImGui_Text(
                ctx,
                '\nIt does not support importing chords with inversions and can only\nimport songs with a 4/4 time signature.\n\nMake sure to copy the data from OneMotion\'s "Edit All" dialog with units \nset to "Beat."\n\n '
            )
            rv, import_key =
                r.ImGui_InputTextMultiline(
                ctx,
                "Import Key",
                import_key,
                35,
                22,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
            r.ImGui_SameLine(ctx)
            if r.ImGui_Button(ctx, "Convert clipboard: OneMotion >> Numbers2Notes format format", nil, nil) then
                import_onemotion()
            end
            r.ImGui_InputTextMultiline(
                ctx,
                "##onemotionimport",
                onemotionimport,
                592,
                321,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        if feedback_tab_mode == 5 and export_tab_mode == 1 then
				reaper.ImGui_Text(ctx, '\n1) Fill in all info including the BIAB style.\n2) In Band in a Box, go to the Edit menu.\n3) Select "Paste Special - from Clipboard text to Song(s) "Ctrl Shift V"\n4) Select "Paste as New Song"\n5) Click OK.\n6) Return to the Edit menu\n7) Again select "Paste Special - from Clipboard text to Song(s)...\n8) Select "Paste into Current Song"\n9) Click OK.\n')
		 

		
				reaper.ImGui_Separator(ctx)
			
		rv, biab_style = r.ImGui_InputTextMultiline(
                ctx,
                "BIAB sytle",
                biab_style,
                200,
                23,
                reaper.ImGui_InputTextFlags_AllowTabInput())
				reaper.ImGui_SameLine(ctx)
				if r.ImGui_Button(ctx, "Convert song to BIAB paste-in format", nil , nil) then
                export_biab()
				end
		
		
				
                rv, biab_export_area =
                r.ImGui_InputTextMultiline(
                ctx,
                "##biab_export_area",
                biab_export_area,
                592,
                186,
				
				
				
                reaper.ImGui_InputTextFlags_AllowTabInput())
				student = false
				beta = true
				if student then
				reaper.ImGui_Text(ctx,'Students...\n')
				reaper.ImGui_Text(ctx,'1) Audition and select your style here:\n')
				Link("https://tinyurl.com/StylePick09844879") -- hidden database
				reaper.ImGui_Text(ctx,'2) Copy your selected style\'s "Copy Code" in 1st column.\n3) Paste the code into the BIAB Style blank above.\n4) Press the blue "Convert song to BIAB..." button\n5) Copy the output data and paste it in the form at this site...\n' )
		Link("https://tinyurl.com/MySong09844879")  -- hidden Form
				reaper.ImGui_Text(ctx,"6) Download your files here...\n" )
		Link("https://tinyurl.com/Song09844879")	-- hidden files
		
				elseif beta then
				reaper.ImGui_Text(ctx,'Beta Testers you can send me your output and I will try to post your \nfiles online for you. Please be patient it is not an automated process.\n')
				reaper.ImGui_Text(ctx,'1) Audition and select your style here:\n')
				Link("https://tinyurl.com/StylePick") -- hidden database
				reaper.ImGui_Text(ctx,'2) Copy your selected style\'s "Copy Code" in 1st column.\n3) Paste the code into the BIAB Style blank above.\n4) Press the blue "Convert song to BIAB..." button\n5) Copy the output data and paste it in the form at this site...\n' )
			Link("https://forms.gle/RfxEzBAWyewdvrxdA")  -- hidden Form
				reaper.ImGui_Text(ctx,"6) Download your files here...\n" )
		Link("https://drive.google.com/drive/folders/1j2r9rmD8FPajjOPlTYCS6lCdYB_bvR2E?usp=sharing")	-- hidden files			
				
				else
				
				end
		
		
		
        end
        if feedback_tab_mode == 5 and export_tab_mode == 2 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for exporting to OneMotion.Com's \nChord Player.\n"
            )

            Link("https://www.onemotion.com/chord-player/")

            reaper.ImGui_Text(
                ctx,
                '\nIt does not support exporting chords with inversions. Make sure to copy\nthe data from OneMotion\'s "Edit All" dialog with units set to "Beat."\n\n'
            )

            --if r.ImGui_Button(ctx, "Convert Chords: Numbers2Notes >> OneMotion Chord Player format", nil, nil) then
            --    render_onemotion()
            --end
            if r.ImGui_Button(ctx, "Convert Numbers2Notes >> OneMotion Chord Player format", nil, nil) then
                Export_OM()
            end
            r.ImGui_InputTextMultiline(
                ctx,
                "##onemotionoutput",
                onemotionoutput,
                592,
                401,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        if feedback_tab_mode == 5 and export_tab_mode == 3 then
            reaper.ImGui_Text(
                ctx,
                "\nNumbers2Notes provides some support for exporting to Chordsheet.Com's \nfree chord chart PDF creation service.\n\nA few things to keep in mind.\n\n  - Only quarter note changes are supported.\n  - Up to 8 chords per bar can be shown but no rhythms will be\n       indicated. Of course you can manually add them by writing\n       them on your print-outs.\n  - Custom links have a 2000 character limit, so very long chord\n       charts may not transfer in their entirety. You may wish to\n       render them in smaller chunks\n  - When you open the link you will need to save to see your PDF.\n  - Download to print.\n  - If you want to save your chord chart at Chordsheet.com, you\n       will need to sign up for their free membership.\n  - The owner of the site has been super cooperative. Please\n       support his efforts.\n\n"
            )

			if ccc_renderd == true then
						if r.ImGui_Button(ctx, "Update my custom link.", nil , nil) then export_ccc() end			
			
			reaper.ImGui_Text(
                ctx,
                '\n\nYour custom link...\n\n'
				) 
			Link(ccclink)
			
			else
						if r.ImGui_Button(ctx, "Create my custom link.", nil , nil) then export_ccc() end
			end


        end

        if feedback_tab_mode == 6 then
            reaper.ImGui_Text(ctx, "Chord and Progression Popularity")
            reaper.ImGui_Separator(ctx)
            reaper.ImGui_Text(ctx, "For more detailed, up-to-date information see:\n")
            Link("https://www.hooktheory.com/trends")
            reaper.ImGui_Separator(ctx)
						reaper.ImGui_Dummy(ctx, 4,10)
            for itt = 1, 12, 1 do
                if string.len(musictheory.major_trend_table[itt][1]) == 1 then
                    chordlabler = musictheory.major_trend_table[itt][1] .. " "
                else
                    chordlabler = musictheory.major_trend_table[itt][1]
                end
                if chosentheorychord == itt then
                    if reaper.ImGui_RadioButton(ctx, chordlabler, true) then
                        chosentheorychord = itt
                    end
                else
                    if reaper.ImGui_RadioButton(ctx, chordlabler, false) then
                        chosentheorychord = itt
                    end
                end

                reaper.ImGui_SameLine(ctx)
                the_root_colors = musictheory.root_colors[musictheory.major_trend_table[itt][4]]
                thecolor =
                    reaper.ImGui_ColorConvertDouble4ToU32(
                    the_root_colors[1] * (1.0 / 255.0),
                    the_root_colors[2] * (1.0 / 255.0),
                    the_root_colors[3] * (1.0 / 255.0),
                    1
                )

                reaper.ImGui_PushStyleColor(ctx, reaper.ImGui_Col_PlotHistogram(), thecolor)
                reaper.ImGui_ProgressBar(
                    ctx,
                    musictheory.major_trend_table[itt][2] / 50,
                    500,
                    20,
                    musictheory.major_trend_table[itt][2] .. "% of chords"
                )
                reaper.ImGui_PopStyleColor(ctx, 1)
            end
			reaper.ImGui_Dummy(ctx, 4,10)
            reaper.ImGui_Separator(ctx)
			reaper.ImGui_Dummy(ctx, 4,10)
            reaper.ImGui_Text(ctx, musictheory.major_trend_table[chosentheorychord][1] .. " Moves to...")
            next_chords = musictheory.major_trend_table[chosentheorychord][3]
            for i1, v1 in pairs(next_chords) do
                if string.len(v1[1]) == 1 then
                    followchordlable = v1[1] .. "  "
                elseif string.len(v1[1]) == 2 then
                    followchordlable = v1[1] .. " "
                else
                    followchordlable = v1[1] .. ""
                end
                if i1 > 6 then
                    reaper.ImGui_SameLine(ctx)

                    reaper.ImGui_Text(ctx, "   ")
                    reaper.ImGui_SameLine(ctx)
                    reaper.ImGui_Text(ctx, v1[1])
                    reaper.ImGui_SameLine(ctx)
                    --reaper.ImGui_ProgressBar(ctx, musictheory.major_trend_table[itt][2] / 50, 500, 20, musictheory
                    rooty = string.gsub(v1[1], "m", "")

                    the_root_colors = musictheory.root_colors[rooty]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, v1[2] .. "% of the time", v1[2] * 10, nil)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                else
                    reaper.ImGui_Text(ctx, followchordlable)
                    reaper.ImGui_SameLine(ctx)
                    --reaper.ImGui_ProgressBar(ctx, musictheory.major_trend_table[itt][2] / 50, 500, 20, musictheory
                    rooty = string.gsub(v1[1], "m", "")

                    the_root_colors = musictheory.root_colors[rooty]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, v1[2] .. "% of the time", v1[2] * 10, nil)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                end
            end
        end

        if feedback_tab_mode == 7 then
            reaper.ImGui_Text(ctx, "Classic Chord Progressions")
            reaper.ImGui_SameLine(ctx)
            Link("https://www.hooktheory.com/theorytab/common-chord-progressions")

            reaper.ImGui_Separator(ctx)

            for i, v in pairs(musictheory.chains_table) do
                reaper.ImGui_Separator(ctx)
                reaper.ImGui_Text(ctx, "       #" .. i .. ") " .. v[1])

                thecolor = reaper.ImGui_ColorConvertDouble4ToU32(.95, .95, .95, 1)
                r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                if i < 10 then
                    if r.ImGui_Button(ctx, "Add #" .. i .. "  -->", nil) then
                        chord_charting_area = chord_charting_area .. "\n" .. v[2] .. "\n"
                    end
                else
                    if r.ImGui_Button(ctx, "Add #" .. i .. " -->", nil) then
                        chord_charting_area = chord_charting_area .. "\n" .. v[2] .. "\n"
                    end
                end

                reaper.ImGui_PopStyleColor(ctx, 1)

                for ji, kv in pairs(v[3]) do
                    reaper.ImGui_SameLine(ctx)

                    the_root_colors = musictheory.root_colors[kv[3]]
                    thecolor =
                        reaper.ImGui_ColorConvertDouble4ToU32(
                        the_root_colors[1] * (1.0 / 255.0),
                        the_root_colors[2] * (1.0 / 255.0),
                        the_root_colors[3] * (1.0 / 255.0),
                        1
                    )
                    r.ImGui_PushStyleColor(ctx, r.ImGui_Col_Button(), thecolor)
                    r.ImGui_Button(ctx, kv[2], 44)
                    reaper.ImGui_PopStyleColor(ctx, 1)
                end
            end
        end

        if feedback_tab_mode == 8 and help_tab_mode == 1 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsample",
                help.Sample_song,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 2 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helptemplate",
                help.Template,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 3 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpcode",
                help.Code_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 4 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsection",
                help.Section_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 5 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpchord",
                help.Chord_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end
        if feedback_tab_mode == 8 and help_tab_mode == 6 then
            r.ImGui_InputTextMultiline(
                ctx,
                "##helpsrhythm",
                help.Rhythm_help,
                592,
                562,
                reaper.ImGui_InputTextFlags_AllowTabInput()
            )
        end

        reaper.ImGui_EndGroup(ctx)

        r.ImGui_PopFont(ctx)
        reaper.ImGui_PopStyleColor(ctx, 22)
        r.ImGui_End(ctx)

    -- BUTTONS
    end
    if open then
        r.defer(IM_GUI_Loop)
    else
        reaper.ImGui_DestroyContext(ctx)

			
	Autosave()
			

			
    end
end

--  ________________________________________________________			ADDITIONAL VARIABLES
G_split = 0
G_error_log = "START ERROR LOG - " .. string.char(10)
G_time_signature_top = 4
G_ticks_per_measure = 960
G_track_list = nil
G_track_table = nil
G_region_table = {}
G_modal_on = false
onemotionoutput = ""
inparenthetical = false

chord_table = {}
pushy_chord_table = {}
temp_chord_table = {}
updated_chord_table = {}

chord_splitsection_count = 0
temp_chord_splitsection_count = 0
updated_chord_splitsection_count = 0

--  VARIABLES AND LOOKUP TABLES
j = 0
k = 0
moment = ""
measure = ""
keyshift = 0
foundnum = 0
last_v = 0
rootshift = 0
splitbar = false
chord_type = ""
measurelist = {}

unstarted = true

current_key = ""

inprogress = false

current_chorded_root = "C"
running_ppqpos_total = 0
measuremultiplelist = {}

last_char_is_o_bracket = false

-- ________________________________________________________ ADDITIONAL FUNCTIONS________________________________



-- ____________________________________________  SET THE SIMULATED USER INPUT DATA  ____________________

function Set_The_Current_Simulated_Userinput_Data(datachunk)
    datachunk = datachunk .. " "
    return datachunk
end

-- ________________________________________________________ SET UP TRACKS

function Setup_Tracks() -- ERASE OLD TRACK (IF NEEDED) AND SET UP A REPLACEMENT
    local sut_tracklist = {}
    local sut_current_track = ""
    local sut_current_trackname = ""
    local track_count
    local sut_track_item_count

    local found_bool_chart = false
    local found_bool_lead_MIDI = false
    local found_bool_chord_MIDI = false
    local found_bool_bass_MIDI = false
    local found_bool_chbass_MIDI = false
    local found_bool_grid_MIDI = false
    local found_bool_lead1 = false
    local found_bool_lead2 = false
    local found_bool_chord_sus = false
    local found_bool_chord_bluearp = false
    local found_bool_chord_librearp = false
    local found_bool_chord_stfu1 = false
    local found_bool_chord_stfu2 = false
    local found_bool_chord_stochas = false
    local found_bool_bass_sus = false
    local found_bool_bass_bluearp = false
    local found_bool_bass_librearp = false
    local found_bool_bass_stfu1 = false
    local found_bool_bass_stfu2 = false
    local found_bool_drums = false	
    local found_bool_chbass_merlittzer = false
    local found_bool_grid_librearp = false
    local found_bool_reverb = false

    local trackID_chart = ""
    local trackID_lead_MIDI = ""
    local trackID_chord_MIDI = ""
    local trackID_bass_MIDI = ""
    local trackID_chbass_MIDI = ""
    local trackID_grid_MIDI = ""
    local trackID_lead1 = ""
    local trackID_lead2 = ""
    local trackID_chord_sus = ""
    local trackID_chord_bluearp = ""
    local trackID_chord_librearp = ""
    local trackID_chord_stfu1 = ""
    local trackID_chord_stfu2 = ""
    local trackID_chord_stochas = ""
    local trackID_bass_sus = ""
    local trackID_bass_bluearp = ""
    local trackID_bass_librearp = ""
    local trackID_bass_stfu1 = ""
    local trackID_bass_stfu2 = ""
    local trackID_drums = ""	
    local trackID_chbass_merlittzer = ""
    local trackID_grid_librearp = ""
    local trackID_reverb = ""

    -- 0 = Table Column Descriptions
    local track_table = {
        [0] = {"Name","found?bool","trackID","clear contents required?",
            {{"plugin 1 | enabled? = this boolean --->",true},{"plugin 2",false}},
            "Sends","Volume = MIDI 0 = No 1 = Yes","Color"},
        [1] = {"N2N Chart", found_bool_chart, trackID_chart, 1, {{"SwingProjectMIDI",true}}, {}, 0, {100, 100, 100}},
        [2] = {"N2N Grid & Reverb", found_bool_grid_MIDI, trackID_grid_MIDI, 1, {{"JS:Lexikan",true}}, {}, 1, {250, 250, 250}},
		-- =========================================================================================================================
        [3] = {"N2N Lead MIDI", found_bool_lead_MIDI, trackID_lead_MIDI, 1, {}, 
			{4}, 1, {108, 162, 123}},
        [4] = {"N2N Lead", found_bool_lead1, trackID_lead1, 0,
			{{"Wait-A-Moment",true},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"pad-synth.jsfx",true},{"Calibre",true},{"Isolator",true}, {"Holt",true}}, 
			{2}, 0, {108, 162, 123}},		
		-- =========================================================================================================================
        [5] = {"N2N Chords MIDI", found_bool_chord_MIDI, trackID_chord_MIDI, 1, {}, 
			{6, 7, 8}, 1, {134, 172, 181}},
        [6] = {"N2N Chord Sustain",found_bool_chord_sus,trackID_chord_sus,0,
			{{"Wait-A-Moment",true},{"ReaPulse",false},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"pad-synth.jsfx",true},{ "Calibre",true},{ "Isolator",true},{ "Holt",true}},
			{2},0,{134, 172, 181}},
        [7] = {"N2N Chord + LibreARP",found_bool_chord_librearp,trackID_chord_librearp,0,
			{{"Wait-A-Moment",true},{"LibreARP",true},{ "ReaPulse",false},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{ "pad-synth.jsfx",true},{ "Calibre",true},{ "Isolator",true},{ "Holt",true},{ "STFU",false}},
			{2},0,{134, 172, 181}},
		[8] = {"N2N Chord + STFU",found_bool_chord_stfu1,trackID_chord_stfu1,0,
			{{"Wait-A-Moment",true},{"ReaPulse",true},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"pad-synth.jsfx",true},{"Calibre",true},{"Isolator",true},{"Holt",true},{"STFU",false},{"STFU",false}},
			{2},0,{134, 172, 181}},
		-- =========================================================================================================================		
        [9] = {"N2N Chord-Bass MIDI", found_bool_chbass_MIDI, trackID_chbass_MIDI, 1, {}, 
			{10}, 1, {172, 134, 181}},
		[10] = {"N2N Chord and Bass + Merlittzer",found_bool_chbass_merlittzer,trackID_chbass_merlittzer,0,
			{{"Wait-A-Moment",true},{"ReaPulse",false},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"MK Merlittzer",true},{"STFU",false}},
			{2},0,{172, 134, 181}},
		-- =========================================================================================================================
        [11] = {"N2N Bass MIDI", found_bool_bass_MIDI, trackID_bass_MIDI, 1, {}, 
			{12, 13, 14}, 1, {134, 153, 181}},
		[12] = {"N2N Bass",found_bool_bass_sus,trackID_bass_sus,0,
			{{"Wait-A-Moment",true},{"ReaPulse",false},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"pad-synth.jsfx",true},{ "Calibre",true},{ "Isolator",true},{ "Holt",true},{"STFU",false}},
			{2},0,{134, 153, 181}},
		[13] = {"N2N Bass + LibreARP",found_bool_bass_librearp,trackID_bass_librearp,0,
			{{"Wait-A-Moment",true},{"LibreARP",true},{ "ReaPulse",false},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{ "pad-synth.jsfx",true},{ "Calibre",true},{ "Isolator",true},{ "Holt",true},{ "STFU",false}},
			{2},0,{134, 153, 181}},
		[14] = {"N2N Bass + STFU",found_bool_bass_stfu1,trackID_bass_stfu1,0,
			{{"Wait-A-Moment",true},{"ReaPulse",true},{"SwingTrackMIDI",true},{"ReaCenterMIDIpitch",false},{"pad-synth.jsfx",true},{"Calibre",true},{"Isolator",true},{"Holt",true},{"STFU",false},{"STFU",false}},
			{2},0,{134, 153, 181}},
		-- =========================================================================================================================			
		[15] = {"N2N Drums",found_bool_drums,trackID_drums,0,
			{{"Tattoo",true},{"SwingTrackMIDI",true},{"Sitala",true},{"Calibre",true}},
			{2},0,{144, 144, 144}}	
		}

    --Show_To_Dev("Started: " .. string.char(10))
    track_count = reaper.CountTracks(0)
    for i = 0, track_count - 1, 1 do -- CHECK EACH TRACK FOR ONE NAMED "Charted Track'
        --Show_To_Dev(i .. string.char(10))
        local sut_current_track_id = reaper.GetTrack(0, i)
        --Show_To_Dev(tostring(sut_current_track_id) .. string.char(10))

        _, sut_current_trackname = reaper.GetTrackName(sut_current_track_id)
        --Show_To_Dev(sut_current_trackname .. string.char(10))

        for i, v in pairs(track_table) do
            if sut_current_trackname == v[1] then
                track_table[i][2] = true
                track_table[i][3] = sut_current_track_id
                track_color = reaper.ColorToNative(v[8][1], v[8][2], v[8][3]) | 0x10000000
                reaper.SetTrackColor(sut_current_track_id, track_color)
            else
            end
            --Show_To_Dev(i .. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
        end
    end
    for i, v in pairs(track_table) do
        if v[2] == true and v[4] == 1 then
            local current_working_track = track_table[i][3]
            --Show_To_Dev("yes " .. i.. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
            sut_track_item_count = reaper.CountTrackMediaItems(current_working_track)
            --Show_To_Dev("track item count =  " .. sut_track_item_count .. string.char(10))
            for i = sut_track_item_count, 1, -1 do
                --Show_To_Dev("current working track =  " .. tostring(current_working_track) .. " | i = " 	.. i .. string.char(10))

                item_index = reaper.GetTrackMediaItem(current_working_track, i - 1)
                --Show_To_Dev("item_index =  " .. tostring(item_index) .. string.char(10))
                reaper.DeleteTrackMediaItem(current_working_track, item_index)
            end
        elseif v[2] == false then
            reaper.InsertTrackAtIndex(i - 1, false) -- INSERT A NEW TRACK
            newly_created_track = reaper.GetTrack(0, i - 1)
            --Show_To_Dev(tostring(newly_created_track) .. string.char(10))
            reaper.GetSetMediaTrackInfo_String(newly_created_track, "P_NAME", v[1], true)
            track_table[i][3] = newly_created_track
            --Show_To_Dev("yes " .. i.. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
            plug_order = 1000
			count = 0
            for j, value in pairs(v[5]) do
                reaper.TrackFX_AddByName(v[3], v[5][j][1], false, plug_order) -- ADD INSTRUMENT FX
				
				reaper.TrackFX_SetEnabled(newly_created_track, count, v[5][j][2])
				count = count + 1
                plug_order = plug_order - 1
            end
        end
    end

    for i, v in pairs(track_table) do
        if i > 0 and v[2] == false then
            for j, w in pairs(v[6]) do
                --Show_To_Dev("i... " .. i .. " hello... " .. tostring(v[3]) .. " and the send is... " .. tostring(track_table[track_table[i][6][j]][3]) .. string.char(10))
                reaper.CreateTrackSend(v[3], track_table[track_table[i][6][j]][3])
            end
        end
    end
    return sup_tracklist, track_table
end

function Initialize_Track_Setup() -- ERASE OLD TRACK (IF NEEDED) AND SET UP A REPLACEMENT
    reaper.PreventUIRefresh(1)
    local isut_tracklist = {}
    local isut_current_track = ""
    local isut_current_trackname = ""
    local itrack_count
    local isut_track_item_count

    local found_bool_audition = false
    local trackID_audition = ""

    -- 0 = Table Column Descriptions
    local itrack_table = {
        [0] = {
            "Name",
            "found?bool",
            "trackID",
            "clear contents required?",
            {"plugin 1", "plugin 2"},
            "Sends",
            "Volume = MIDI 0 = No 1 = Yes"
        },
        [1] = {
            "N2N Audition",
            found_bool_audition,
            trackID_audition,
            0,
            {"pad-synth.jsfx", "Isolator"},
            {},
            0,
            {222, 222, 222}
        }
    }

    --Show_To_Dev("Started: " .. string.char(10))
    itrack_count = reaper.CountTracks(0)
    for i = 0, itrack_count - 1, 1 do -- CHECK EACH TRACK FOR ONE NAMED "Charted Track'
        --Show_To_Dev(i .. string.char(10))
        local isut_current_track_id = reaper.GetTrack(0, i)
        --Show_To_Dev(tostring(isut_current_track_id) .. string.char(10))

        _, isut_current_trackname = reaper.GetTrackName(isut_current_track_id)
        --Show_To_Dev(isut_current_trackname .. string.char(10))

        for i, v in pairs(itrack_table) do
            if isut_current_trackname == v[1] then
                itrack_table[i][2] = true
                itrack_table[i][3] = isut_current_track_id
                itrack_color = reaper.ColorToNative(v[8][1], v[8][2], v[8][3]) | 0x10000000
                reaper.SetTrackColor(isut_current_track_id, itrack_color)
            else
            end
            --Show_To_Dev(i .. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
        end
    end
    for i, v in pairs(itrack_table) do
        if v[2] == true and v[4] == 1 then
            local icurrent_working_track = itrack_table[i][3]
            --Show_To_Dev("yes " .. i.. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
            isut_track_item_count = reaper.CountTrackMediaItems(icurrent_working_track)
            --Show_To_Dev("track item count =  " .. isut_track_item_count .. string.char(10))
            for i = isut_track_item_count, 1, -1 do
                --Show_To_Dev("current working track =  " .. tostring(icurrent_working_track) .. " | i = " 	.. i .. string.char(10))

                iitem_index = reaper.GetTrackMediaItem(icurrent_working_track, i - 1)
                --Show_To_Dev("item_index =  " .. tostring(iitem_index) .. string.char(10))
                reaper.DeleteTrackMediaItem(icurrent_working_track, iitem_index)
            end
        elseif v[2] == false then
            reaper.InsertTrackAtIndex(i - 1, false) -- INSERT A NEW TRACK
            inewly_created_track = reaper.GetTrack(0, i - 1)
            --Show_To_Dev(tostring(newly_created_track) .. string.char(10))
            reaper.GetSetMediaTrackInfo_String(inewly_created_track, "P_NAME", v[1], true)
            itrack_table[i][3] = inewly_created_track
            --Show_To_Dev("yes " .. i.. " " .. tostring(v[2]) .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. string.char(10))
            iplug_order = 1000
            for j, value in pairs(v[5]) do
                reaper.TrackFX_AddByName(v[3], v[5][j], false, iplug_order) -- ADD INSTRUMENT FX
                iplug_order = iplug_order - 1
            end
        end
    end

    for i, v in pairs(itrack_table) do
        if i > 0 and v[2] == false then
            for j, w in pairs(v[6]) do
                --Show_To_Dev("i... " .. i .. " hello... " .. tostring(v[3]) .. " and the send is... " .. tostring(itrack_table[itrack_table[i][6][j]][3]) .. string.char(10))
                reaper.CreateTrackSend(v[3], itrack_table[itrack_table[i][6][j]][3])
            end
        end
    end
    SetVMidiInput(1, "Virtual MIDI Keyboard")
    reaper.PreventUIRefresh(-1)
    return isup_tracklist, itrack_table
end



function inital_swaps(chunky1)
    databoy = string.gsub(chunky1, "%^%^", "~")
    --[[
	databoy = string.gsub(databoy, " r ", " - ")
	databoy = string.gsub(databoy, " R ", " - ")
	databoy = string.gsub(databoy, " r" .. string.char(10), " -" .. string.char(10))
	databoy = string.gsub(databoy, " R" .. string.char(10), " -" .. string.char(10))
	databoy = string.gsub(databoy, string.char(10) .. "r ", string.char(10) .. "- ")
	databoy = string.gsub(databoy, string.char(10) .. "R ", string.char(10) .. "r ")
	databoy = string.gsub(databoy, string.char(10) .. "r" .. string.char(10), string.char(10) .. "-" .. string.char(10))
	databoy = string.gsub(databoy, string.char(10) .. "R" .. string.char(10), string.char(10) .. "-" .. string.char(10))
	databoy = string.gsub(databoy, "(r ", "(- ")
	databoy = string.gsub(databoy, "(R ", "(- ")
	databoy = string.gsub(databoy, "(r)", "(-)")
	databoy = string.gsub(databoy, "(R)", "(-)")
	databoy = string.gsub(databoy, " r)", " -)")
	databoy = string.gsub(databoy, " R)", " -)")
	--Show_To_Dev(databoy)
]]
    return databoy
end


-- ____________________________________________  SET THE KEY  ____________________



function Autosave()
			_, quit_title_startso  = string.find(header_area, "Title: ")			-- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
			quit_title_endso, _  = string.find(header_area, "Writer:")
			
			quittitlefound = string.sub(header_area, quit_title_startso+1, quit_title_endso-2)
			thetime = os.date('%Y-%m-%d %H-%M-%S')
			if string.len(quittitlefound) < 30 and quittitlefound ~= nil then

			filenamewillbe = quittitlefound .. " " .. thetime .. ".txt"
			else
			filenamewillbe = "N2Nautobackup " .. thetime .. ".txt"
			end
			
			local info = debug.getinfo(1,'S')
			local path = info.source:match[[^@?(.*[\/])[^\/]-$]]
			local chordchart_path = path .. 'ChordCharts/'
			--retval, fileName =
			--	reaper.JS_Dialog_BrowseForSaveFile(
			--	"Save Chord Chart as...",
			--	chordchart_path,
			--	filenamewillbe,
			--	".txt"
			--)

			write_path = io.open(chordchart_path..filenamewillbe, "w")
			write_path:write("<Numbers2NotesProject>\n<header_area>\n"..header_area .."\n</header_area>\n<chord_charting_area>\n"..chord_charting_area.."\n</chord_charting_area>\n<lyrics_charting_area>\n"..lyrics_charting_area.."\n</lyrics_charting_area>\n<notes_charting_area>\n"..notes_charting_area.."\n</notes_charting_area>\n</Numbers2NotesProject>")
			write_path:close()	

end
















function set_the_key(stk_progression)
    starting_key = ""
    _, key_endchar = string.find(stk_progression, "Key:")
    if key_endchar == nil then
        --Show_To_Dev("Key not set. Rendered in the Key of C" .. string.char(10))
        starting_key = "C"
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where Key was not on it's own line. Rendered in C." .. string.char(10))
            starting_key = "C"
        else
            key_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("keyline = '" .. key_line .. "'" .. string.char(10))
            for i = 1, string.len(key_line), 1 do
                if string.sub(key_line, i, i) == " " then
                    --Show_To_Dev("keyline character = space" .. string.char(10))
                else
                    --Show_To_Dev("keyline character = '" .. string.sub(key_line, i, i) ..  "'" .. string.char(10))
                    starting_key = starting_key .. string.sub(key_line, i, i)
                end
            end
            if musictheory.key_table[starting_key] == nil then
                --Show_To_Dev("Key '" .. starting_key .. "' not found - Rendered in the Key of C" .. string.char(10))
                starting_key = "C"
            else
                --Show_To_Dev("Key set to " .. starting_key .. string.char(10))
            end
        end
    end
    return starting_key
end

-- ____________________________________________  SET THE BPM  ____________________

function set_the_bpm(stk_progression)
    project_bpm, project_bpi = reaper.GetProjectTimeSignature2(0)
    stk_progression = stk_progression .. string.char(10)

    starting_bpm = ""
    _, key_endchar = string.find(stk_progression, "BPM:")
    if key_endchar == nil then
        Show_To_Dev("BMP not set." .. string.char(10))
        starting_bpm = project_bpm
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where BPM was not on it's own line. Rendered in C." .. string.char(10))
            starting_bpm = project_bpm
        else
            BPM_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("BPM_line = '" .. BPM_line .. "'" .. string.char(10))
            for i = 1, string.len(BPM_line), 1 do
                if string.sub(BPM_line, i, i) == " " then
                    --Show_To_Dev("BPM_line character = space" .. string.char(10))
                else
                    --Show_To_Dev("BPM_line character = '" .. string.sub(BPM_line, i, i) ..  "'" .. string.char(10))
                    starting_bpm = starting_bpm .. string.sub(BPM_line, i, i)
                end
            end
            number_from_string = tonumber(string.match(starting_bpm, "%d+"))
            if number_from_string == nil then
                --Show_To_Dev("BPM '" .. starting_bpm .. "' not found - Project tempo left unchanged" .. string.char(10))
                starting_bpm = project_bpm
            else
                if number_from_string < 2 or number_from_string > 960 then
                    render_feedback =
                        render_feedback ..
                        "BPM '" ..
                            number_from_string ..
                                "' out of range (Minimum = 2 and Maximum = 960) \nProject tempo left unchanged.\n_____________" ..
                                    string.char(10)
                    starting_bpm = project_bpm
                else
                    starting_bpm = number_from_string
                    reaper.SetCurrentBPM(0, number_from_string, true)
                    --Show_To_Dev("Tempo set to " .. starting_bpm .. string.char(10))
                    render_feedback = render_feedback .. "BPM set to " .. number_from_string .. string.char(10)
                end
            end
        end
    end
    --reaper.ShowConsoleMsg("=======BPM=======" .. starting_bpm .. "=======BPM=======")
    return starting_bpm
end

-- ____________________________________________  SET THE SWING  ____________________

function set_the_swing(stk_progression)
    project_swing = 0
    stk_progression = stk_progression .. string.char(10)

    starting_swing = ""
    _, key_endchar = string.find(stk_progression, "Swing")
    if key_endchar == nil then
        Show_To_Dev("Swing not set." .. string.char(10))
        starting_swing = project_swing
    else
        return_char_location, _ =
            string.find((string.sub(stk_progression, key_endchar + 1, string.len(stk_progression))), string.char(10))
        --Show_To_Dev("return location: " .. return_char_location .. string.char(10))
        if return_char_location == nil then
            --Show_To_Dev("Odd situation where Swing was not on it's own line. Rendered in C." .. string.char(10))
            the_swing = 0
        else
            swing_line = string.sub(stk_progression, key_endchar + 1, key_endchar + return_char_location - 1)
            --Show_To_Dev("swing_line = '" .. swing_line .. "'" .. string.char(10))
            for i = 1, string.len(swing_line), 1 do
                if string.sub(swing_line, i, i) == " " then
                    --Show_To_Dev("swing_line character = space" .. string.char(10))
                else
                    --Show_To_Dev("swing_line character = '" .. string.sub(swing_line, i, i) ..  "'" .. string.char(10))
                    starting_swing = starting_swing .. string.sub(swing_line, i, i)
                end
            end
            number_from_string = tonumber(string.match(starting_swing, "%d+"))
            if number_from_string == nil then
                --Show_To_Dev("Swing '" .. starting_swing .. "' not found - Project tempo left unchanged" .. string.char(10))
                starting_swing = project_swing
            else
                if number_from_string < 0 or number_from_string > 100 then
                    render_feedback =
                        render_feedback ..
                        "Swing '" ..
                            number_from_string ..
                                "' out of range (Minimum = 0 and Maximum = 100) \nSwing set to 0.\n_____________" ..
                                    string.char(10)
                    starting_swing = project_swing
                else
                    starting_swing = number_from_string
					reaper.gmem_attach("ProjectSwing")
					reaper.gmem_write(2, starting_swing)
					
                    render_feedback = render_feedback .. "Swing set to " .. number_from_string .. string.char(10)
                end
            end
        end
    end
    --reaper.ShowConsoleMsg("=======BPM=======" .. starting_bpm .. "=======BPM=======")
    return starting_bpm
end



-- ______________________________________________ORGANIZE INPUTS INTO BARS

function orgainize_input_into_bars(oiib_error_log) -- PLACE ALL THE USER INPUT INTO AN ORGANIZED TABLE
    local oiib_split = 0
    local oiib_measurecount = 0
    local oiib_inmeasure = false
    local oiib_last_char_is_space = true
    local oiib_measuremultiple = 1
    j = 1
    ::testchar::
    for i = j, string.len(progression), 1 do -- PROCESS EACH CHARACTER OF USER INPUT
        if string.sub(progression, i, i) == "{" and string.sub(progression, i + 1, i + 1) == "$" then
            section_close_start, section_close_end = string.find(progression, "$}", i + 1)
            section_name = string.sub(progression, i, section_close_end)
            oiib_measurecount = oiib_measurecount + 1
            oiib_measure_ticks = 0
            measuremultiplelist[oiib_measurecount] = oiib_measure_ticks
            table.insert(chord_table, oiib_measurecount, {0, 1, 0, section_name})

            table.insert(chord_table, oiib_measurecount, {0, 1, 0, section_name})
            j = section_close_end + 1
            --Show_To_Dev("THIS HAPPENED!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!" .. string.char(10))
            --Show_To_Dev(section_name .. string.char(10))
            goto testchar
        elseif
            string.byte(progression, i) == 32 or string.byte(progression, i) == 10 or string.byte(progression, i) == 13 or
                string.byte(progression, i) == 9
         then --  WHEN CHARACTER IS A SPACER (SPACE, TAB, RETURN)
            if oiib_inmeasure == false then -- WHEN NOT WORKING WITH A SPLIT MEASURE
                if oiib_last_char_is_space == false then -- WHEN NOT AFTER A SPACE
                    oiib_last_char_is_space = true
                    oiib_measurecount = oiib_measurecount + 1
                    oiib_measure_ticks = oiib_measuremultiple * G_time_signature_top * G_ticks_per_measure
                    measuremultiplelist[oiib_measurecount] = oiib_measure_ticks
                    if splitbar == false then
                        table.insert(
                            chord_table,
                            oiib_measurecount,
                            {0, oiib_measuremultiple, oiib_measure_ticks, measure}
                        )
                    else
                        table.insert(
                            chord_table,
                            oiib_measurecount,
                            {1, oiib_measuremultiple, oiib_measure_ticks, measure}
                        )
                    end
                    splitbar = false
                    measure = ""
                    oiib_measuremultiple = 1
                else
                    oiib_last_char_is_space = true -- WHEN AFTER A SPACE
                end
            else -- WHEN WORKING WITH A SPLIT MEASSURE
                if oiib_last_char_is_space == false then -- NOT AFTER A SPACE
                    oiib_last_char_is_space = true
                    measure = measure .. " "
                else -- AFTER A SPACE
                end
            end
        elseif string.byte(progression, i) == 91 then -- CHARACTER IS OPEN BRACKET
            splitbar = true
            if oiib_inmeasure == true then
                oiib_error_log = oiib_error_log .. '\n\nMissing "]" - Not all "split" bars were closed.'
            end
            if oiib_last_char_is_space == true then -- AND LAST CHARACTER WAS A SPACE (NOT A MULTIBAR)
                oiib_inmeasure = true
            else
                oiib_inmeasure = true -- AND LAST CHARACTER WAS A NOT A SPACE (IS A MULTIBAR)
                oiib_measuremultiple = measure
                measure = ""
                oiib_last_char_is_space = true
            end
        elseif string.byte(progression, i) == 93 then -- CHARACTER IS CLOSED BRACKET
            oiib_inmeasure = false -- NOT IN A SPLIT MEASURE
            oiib_last_char_is_space = false
        else -- IN A SPLIT MEASURE
            oiib_last_char_is_space = false
            measure = measure .. string.sub(progression, i, i)
        end
    end
    if oiib_inmeasure == true then
        oiib_error_log = oiib_error_log .. '\n\nMissing "]" - The final bar was not closed.'
    end

    finalcount = 0
    for i, value in pairs(chord_table) do
        finalcount = finalcount + 1
    end

    for i = 1, finalcount, 1 do
        if chord_table[i][4] == "%" then --  PROCESS BAR REPEATS
            ----Show_To_Dev(chord_table[i][4]  .. " yes | " .. string.char(10))
            chord_table[i] = chord_table[i - 1]
        else
            ----Show_To_Dev(chord_table[i][4]  .. " no | " .. string.char(10))
        end
    end

    chord_splitsection_count = oiib_measurecount
    for i, v in pairs(chord_table) do
        --Show_To_Dev("YO!... " .. tostring(v[1])  .. " | " .. tostring(v[2])  .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. " | " .. string.char(10))
    end
    return oiib_split, oiib_error_log
end

-- _______________________________________________________________________  PROCESS EACH CHARACTER OF USER INPUT  ____________________
function process_data_chunks(
    pdc_chord_table,
    pdc_chord_splitsection_count,
    pdc_current_chunk_data,
    pdc_split,
    pdc_error_log)
    local pdc_section_in_progress = false
    local pdc_chord_in_progress = false
    local pdc_parenthetical_depth = 0
    local pdc_multiple = 1
    for i = 1, string.len(pdc_current_chunk_data), 1 do -- PROCESS EACH CHARACTER OF USER INPUT
        if
            string.byte(pdc_current_chunk_data, i) == 32 or string.byte(pdc_current_chunk_data, i) == 9 or
                string.byte(pdc_current_chunk_data, i) == 10 or
                string.byte(pdc_current_chunk_data, i) == 13
         then
            --  IS THE CHARACTER IS A SPACER (SPACE, TAB, RETURN)               SPACE
            if pdc_section_in_progress == true then --  AND IN THE MIDST OF PROCESSING A SPLIT SECTION
                pdc_current_chord = pdc_current_chord .. " " --  CONVERT TO SPACE
            elseif pdc_chord_in_progress == true then --  IF IT ISN'T A SPLIT SECTION, BUT OCCURS AFTER THE PROGRESS OF WORKING WITH A SINGLE CHORD
                pdc_chord_splitsection_count = pdc_chord_splitsection_count + 1 --  THEN THERE A NEW CHORD HAS BEEN PROCESSED ADD IT TO THE COUNT
                pdc_split = pdc_split + pdc_multiple --  CALCULATE HOW MANY PORTIONS THE TIME HAS BEEN SPLIT INTO BY ADDING THE NEW CHORD'S PORTION
                table.insert(pdc_chord_table, pdc_chord_splitsection_count, {0, pdc_multiple, 1, pdc_current_chord})
                --  INSERT THE NEW CHORD INTO THE TABLE OF CHORDS
                --  {0 = NOT A SPLIT, MULTIPLE = 1 BECAUSE IT IS NOT SPLIT, 1 IS A PLACE HOLDER, THE CHORD)
                pdc_current_chord = "" --  CLEAR THE CURRENT CHORD VARIABLE SO IT'S READY FOR THE NEXT CHORD
                pdc_chord_in_progress = false --  STARTING FRESH IN THE SEARCH FOR THE NEXT CHORD = THERE IS NO CURRENT CHORD STARTED
                pdc_multiple = 1 --  THE MULTIPLE IS RESET TO 1 WHICH IS THE DEFAULT
            elseif pdc_chord_in_progress == false then --  IF THERE IS NO CHORD OR SECTION IN PROGRESS THEN THE SPACER IS NOT NEEDED
            else
                pdc_error_log = pdc_error_log .. "error 1 - Something wrong with input or program." .. string.char(10) --  IF NONE OF THESE IS THE CASE THERE MUST BE AN ERROR IN THE CODE OR THE USER ENTRY
            end
        elseif string.byte(pdc_current_chunk_data, i) == 40 then --  WHEN CHARACTER IS AN OPEN PARENTHESIS                           (
            pdc_parenthetical_depth = pdc_parenthetical_depth + 1 --  EACH "(" THAT SHOWS UP TAKES US A LEVEL DEEPER IN THE SPLITTING OF THE BAR AND BEATS
            --  THIS COUNT IS NEEDED TO MAKE SURE THAT THE USER CLOSES ALL OPEN PARANTHESIS WITH CLOSES
            if pdc_section_in_progress == true then --  IF A SECTION IS ALREADY IN PROGRESS IT IS SIMPLY STORED TO DEAL WITH LATER
                pdc_current_chord = pdc_current_chord .. "("
            elseif pdc_chord_in_progress == false then --  IF THERE IS NO SPLIT SECTION OR CHORD IN PROGRESS THE "(" WOULD SIGNIFY THE START OF A NEW SPLIT SECTION
                pdc_chord_in_progress = false
                pdc_section_in_progress = true
                pdc_current_chord = ""
            else --  THIS WOULD ONLY OCCUR WHEN THERE IS A MULTIPLE BEFORE THE START OF A SECTION
                pdc_section_in_progress = true
                pdc_chord_in_progress = false
                pdc_multiple = pdc_current_chord --  SO STORE THE MULTIPLE AND CLEAR THE CURRENT CHORD VARIABLE TO GET READY TO START STORING A NEW SECTION
                pdc_current_chord = ""
            end
        elseif string.byte(pdc_current_chunk_data, i) == 41 then --  WHEN CHARACTER IS AN OPEN PARENTHESIS                           )
            pdc_parenthetical_depth = pdc_parenthetical_depth - 1 --  pdc_parenthetical_depth IS REDUCED TO SHOW ONE SPLIT HAS BEEN CLOSED
            if pdc_parenthetical_depth < 0 then --  SINCE THERE SHOULD NEVER BE A CLOSE WITHOUT A CORRESPONDING OPENING HAVING HAPPENED FIRST,
                --  A NEGATIVE INDICATES AN ERROR IN THE USER INPUT
                pdc_error_log = pdc_error_log .. string.char(10) .. "Missing close parenthesis" .. string.char(10)
            elseif pdc_parenthetical_depth == 0 and pdc_section_in_progress == true then
                --  A pdc_parenthetical_depth OF 0 INDICATES THAT THE INTERNAL AND OVERALL SPLIT SECTIONS HAVE BEEN CLOSED
                pdc_chord_splitsection_count = pdc_chord_splitsection_count + 1 --  SPLIT COMPLETED AND ADDED TO THE COUNT
                pdc_split = pdc_split + pdc_multiple --  TRACKING OF HOW MANY SPLITS HAVE OCCURED IS INCREMENTED BY THE NEW SPLIT'S MULTIPLE
                table.insert(pdc_chord_table, pdc_chord_splitsection_count, {1, pdc_multiple, 1, pdc_current_chord})
                --  ADD THE SPLIT TO THE CHORD TABLE
                pdc_current_chord = "" --  CLEAR THE CURRENT CHORD VARIABLE TO PREP FOR THE NEXT CHORD SEARCH
                pdc_chord_in_progress = false --  STARTING FRESH SO NEITHER A CHORD OR SPLIT IS IN PROGRESS
                pdc_section_in_progress = false
                pdc_multiple = 1 --  MULTIPLE IS RESET TO DEFAULT VALUE OF 1
            elseif pdc_parenthetical_depth > 0 and pdc_section_in_progress == true then --  IF THE SECTION WAS ALREADY IN PROGRESS A POSITIVE VALUE WOULD INDICATED BEING IN THE MIDST OF A
                --  AN ONGOING SPLIT AND THAT THE CLOSE IS INTERNAL AND SIMPLY NEEDS TO BE ADDED TO THE SPLIT IN PROGRESS
                pdc_current_chord = pdc_current_chord .. ")"
            else
                pdc_error_log = pdc_error_log .. "error 2 - Something wrong with input or program." .. string.char(10) --  ANY OTHER OUTCOME INDICATES SOMETHING IS WRONG WITH EITHER THE PROGRAMMING OR THE USER INPUT
            end
        else --  WHEN THE CHARACTER IS ANYTHING ELSE                      FOR EXAMPLE  m, 4, 7, j
            if pdc_section_in_progress == true then --  WHEN IN THE MIDST OF A SPLIT SECTION JUST CONTINUE BY ADDING THE CURRENT CHAR TO THE SPLIT SECTION
                pdc_current_chord = pdc_current_chord .. string.sub(pdc_current_chunk_data, i, i)
            elseif pdc_chord_in_progress == true then --  WHEN IN THE MIDST OF A CHORD JUST CONTINUE BY ADDING THE CURRENT CHAR THE CHORD
                pdc_current_chord = pdc_current_chord .. string.sub(pdc_current_chunk_data, i, i)
            else
                pdc_chord_in_progress = true --  OTHERISE A NEW CHORD OR SPLIT STARTING WITH A MULTIPLE HAS BEGUN - IF IT IS A MULTIPL IT WILL BE DETERMINED LATER
                pdc_current_chord = string.sub(pdc_current_chunk_data, i, i)
                --  CURRENT CHORD = THE CURRENT CHARACTER
                pdc_multiple = 1 --  MULTIPLE SET TO DEFAULT OF 1 WHICH WILL BE CHANGED LATER IN THE CASE OF A MULTIPLE AND SPLIT
            end
        end
    end
    return pdc_chord_table, pdc_chord_splitsection_count, pdc_split, pdc_error_log
end

-- _______________________________________________________________________  DISPLAY THE CHORD TABLE IN THE CONSOLE  ____________________

function presentdata(p_split, p_error_log)
    datapeek = ""
    for i, value in pairs(chord_table) do
        datapeek = datapeek .. string.char(10) .. "i = " .. i .. " | " .. string.char(10)
        k = 0
        for k, v in pairs(value) do
            datapeek = datapeek .. " k = " .. k .. " / value = " .. v .. string.char(10)
        end
    end
    Show_To_Dev(datapeek .. string.char(10))

    --THIS SPLIT IS WRONG !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
    Show_To_Dev("Split = " .. p_split .. string.char(10))
    Show_To_Dev("Error Record:" .. string.char(10) .. p_error_log .. string.char(10))
end

-- _______________________________________________________________________  ASSIGN EACH CHORD AND SPLIT SECTION IT'S PORTION OF TIME  ____________________

function asign_ticks_per_split_portion(at_chord_table, at_chord_splitsection_count, at_ticks_per, at_split)
    for i = 1, at_chord_splitsection_count, 1 do
        at_chord_table[i][3] = (at_chord_table[i][2]) * at_ticks_per / at_split --  BASE # OF TICKS * THE CHORD/SPLIT SECTION's MULTIPL
    end
    return at_chord_table
end

-- _______________________________________________________________________ PROCESS NESTED SPLITS  ____________________

function process_nested_split_sections(pnss_split, pnss_error_log)
    temp_chord_table = chord_table -- MAKE A COPY OF THE CHORD TABLE AND IT'S COUNT
    temp_chord_splitsection_count = chord_splitsection_count
    pnss_updated_chord_split_section_count = 0 -- CREATE NEW TABLES AND COUNTS FOR HOLDING DATA AS IT CHANGES
    pnss_updated_chord_table = {}
    pnss_still_more_nested = false

    for i = 1, temp_chord_splitsection_count, 1 do -- PROCESS THE DATA
        if temp_chord_table[i][1] == 0 then -- IF IT HAS NO SPLIT (0) THEN JUST COPY OVER
            pnss_updated_chord_split_section_count = pnss_updated_chord_split_section_count + 1
            table.insert(pnss_updated_chord_table, pnss_updated_chord_split_section_count, temp_chord_table[i])
        elseif temp_chord_table[i][1] == 1 then -- IF IT HAS A SPLIT (1) THEN
            pnss_still_more_nested = true
            chord_table = {}
            chord_splitsection_count = 0
            pnss_current_chunk_data = temp_chord_table[i][4] .. " "
            pnss_current_chunk_data = pnss_current_chunk_data .. " "
            pnss_split = 0
            --   ______________________________________________________________________     PROCESS DATA CHUNKS FUNCTION TRIGGERED HERE!!!
            chord_table, chord_splitsection_count, pnss_split, pnss_error_log =
                process_data_chunks(
                chord_table,
                chord_splitsection_count,
                pnss_current_chunk_data,
                pnss_split,
                pnss_error_log
            )

            pnss_ticks_per_section = temp_chord_table[i][3]
            --   ______________________________________________________________________        ASSIGN TICKS FUNCTION TRIGGERED HERE!!!
            chord_table =
                asign_ticks_per_split_portion(chord_table, chord_splitsection_count, pnss_ticks_per_section, pnss_split)
            for i = 1, chord_splitsection_count, 1 do
                pnss_updated_chord_split_section_count = pnss_updated_chord_split_section_count + 1
                table.insert(pnss_updated_chord_table, pnss_updated_chord_split_section_count, chord_table[i])
            end
        end
    end

    chord_table = pnss_updated_chord_table
    chord_splitsection_count = pnss_updated_chord_split_section_count
    pnss_updated_chord_table = {}
    pnss_updated_chord_split_section_count = 0
    if pnss_still_more_nested == true then
        pnss_still_more_nested = false
        process_nested_split_sections()
    end
    return pnss_split, pnss_error_log
end

-- _______________________________________________________________________ PLACE TEXT ITEMS

function place_TEXT_data(ptd_track_table)
    local ptd_updating_start_ppqpos = 0
    local ptd_note_end_ppqpos = 0
    local ptd_last_updated_ppqpos = 0
    local ptd_note_end_ppqpos = 0
    local ptd_measure_start_point = 0
    local ptd_measure_end_point = 0
    local ptd_chord_entry_to_text = ""
    local ptd_text_item_count = 0
    local ptd_new_text_item = ""

    for i, value in pairs(chord_table) do
        if string.sub(value[4], 1, 2) == "{$" then
        --Show_To_Dev("DRIVING ME CRAZY...............................!!!!!!!!!!!!!")
        --Show_To_Dev(string.char(10) .. i .. string.char(10))
        end
        ptd_note_end_ppqpos = ptd_updating_start_ppqpos + value[3]
        --Show_To_Dev("text start ppqos: " .. ptd_updating_start_ppqpos .. " end ppqpos: " .. ptd_note_end_ppqpos .. string.char(10))
        ptd_last_updated_ppqpos = ptd_note_end_ppqpos
        if ptd_updating_start_ppqpos == 0 then
            ptd_measure_start_point = 0
        else
            ptd_measure_start_point = ptd_updating_start_ppqpos / (G_ticks_per_measure)
        end
        if i == 1 then
            ptd_first_run_start_point = ptd_measure_start_point
        end
        if ptd_note_end_ppqpos == 0 then
            ptd_measure_end_point = 0
        else
            ptd_measure_end_point = ptd_note_end_ppqpos / (G_ticks_per_measure)
        end

        -- CREATE A TEXT ITEM ON THE TRACK
        ptd_new_MIDI_item =
            reaper.CreateNewMIDIItemInProj(ptd_track_table[1][3], ptd_measure_start_point, ptd_measure_end_point, true)

        text_position = reaper.GetMediaItemInfo_Value(ptd_new_MIDI_item, "D_POSITION")
        text_length = reaper.GetMediaItemInfo_Value(ptd_new_MIDI_item, "D_LENGTH")
        ptd_new_text_item = reaper.AddMediaItemToTrack(ptd_track_table[1][3]) -- Text Item from Track
        reaper.SetMediaItemInfo_Value(ptd_new_text_item, "D_POSITION", text_position)
        reaper.SetMediaItemInfo_Value(ptd_new_text_item, "D_LENGTH", text_length)
        reaper.DeleteTrackMediaItem(ptd_track_table[1][3], ptd_new_MIDI_item)
        ptd_chord_entry_to_text = chord_table[i][4]
        if ptd_chord_entry_to_text == "-" then
            ptd_chord_entry_to_text = "Rest"
        end
        if text ~= nil then
            reaper.ULT_SetMediaItemNote(ptd_new_text_item, ptd_chord_entry_to_text)
        end
        ptd_text_item_count = ptd_text_item_count + 1
        ptd_updating_start_ppqpos = ptd_note_end_ppqpos
        ptd_last_end_point = ptd_measure_end_point
    end

    for i, value in pairs(chord_table) do
        --Show_To_Dev("i check = " .. i .. "value[1] = " .. value[1] .. " value[2] = " .. value[2] .. " value[3] = " .. value[3] .. " value[4] = " .. value[4] .. string.char(10))
    end

    grid_midi_item_id =
        reaper.CreateNewMIDIItemInProj(ptd_track_table[2][3], ptd_first_run_start_point, ptd_last_end_point, true)
    lead_midi_item_id =
        reaper.CreateNewMIDIItemInProj(ptd_track_table[3][3], ptd_first_run_start_point, ptd_last_end_point, true)
    chords_midi_item_id =
        reaper.CreateNewMIDIItemInProj(ptd_track_table[5][3], ptd_first_run_start_point, ptd_last_end_point, true)
    chbass_midi_item_id =
        reaper.CreateNewMIDIItemInProj(ptd_track_table[9][3], ptd_first_run_start_point, ptd_last_end_point, true)
    bass_midi_item_id =
        reaper.CreateNewMIDIItemInProj(ptd_track_table[11][3], ptd_first_run_start_point, ptd_last_end_point, true)

    for i, v in pairs(chord_table) do
        --Show_To_Dev("So!... I = " .. i .. "  " .. tostring(v[1])  .. " | " .. tostring(v[2])  .. " | " .. tostring(v[3]) .. " | " .. tostring(v[4]) .. " | " .. string.char(10))
    end

    return ptd_text_item_count, lead_midi_item_id, chords_midi_item_id, bass_midi_item_id, chbass_midi_item_id, grid_midi_item_id
end

-- _______________________________________________________________________ PLACE MIDI

function place_MIDI_data(
    pmd_text_item_count,
    pmd_lead_midi_item_id,
    pmd_chords_midi_item_id,
    pmd_bass_midi_item_id,
    pmd_chbass_midi_item_id,
    pmd_grid_midi_item_id,
    pmd_track_table)
    local pmd_running_ppqpos_total = 0
    local pmd_note_end_ppqpos = 0
    local pmd_error_log = ""

    local pmd_item_red = 192
    local pmd_item_green = 192
    local pmd_item_blue = 192
    local ptd_rgb_color = {192, 192, 192}

    for i, value in pairs(chord_table) do
        pmd_root = ""
        chord_type = ""
        local pmd_item_to_color = reaper.GetTrackMediaItem(pmd_track_table[1][3], i - 1)
        if string.sub(value[4], 1, 1) == "-" then
            --   																					NON-NOTE SITUATIONS
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            text_item_color = reaper.ColorToNative(133, 133, 133) | 0x1000000
            reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
        elseif (string.sub(value[4], 1, 1) == "b" and musictheory.root_table[string.sub(value[4], 1, 2)] == nil) then
            pmd_error_log =
                pmd_error_log .. "Invalid flat root " .. string.sub(value[4], 1, 2) .. " used." .. string.char(10)
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
            reaper.ULT_SetMediaItemNote(
                pmd_item_to_color,
                '!!! ENTRY ERROR !!! \n"' .. string.sub(value[4], 1, 2) .. '" \nis not a supported chord root.'
            )
            reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            pmd_root = "-"
        elseif (string.sub(value[4], 1, 1) == "#" and musictheory.root_table[string.sub(value[4], 1, 2)] == nil) then
            pmd_error_log =
                pmd_error_log .. "Invalid sharp root " .. string.sub(value[4], 1, 2) .. " used." .. string.char(10)
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
            reaper.ULT_SetMediaItemNote(
                pmd_item_to_color,
                '!!! ENTRY ERROR !!! \n"' .. string.sub(value[4], 1, 2) .. '" \nis not a supported chord root.'
            )
            reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            pmd_root = "-"
        elseif
            (musictheory.root_table[string.sub(value[4], 1, 1)] == nil and string.sub(value[4], 1, 1) ~= "{" and
                string.sub(value[4], 1, 1) ~= "b" and
                string.sub(value[4], 1, 1) ~= "#")
         then
            pmd_error_log =
                pmd_error_log .. "Invalid root character " .. string.sub(value[4], 1, 1) .. " used." .. string.char(10)
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
            reaper.ULT_SetMediaItemNote(
                pmd_item_to_color,
                '!!! ENTRY ERROR !!! \n"' .. string.sub(value[4], 1, 1) .. '" \nis not a supported chord root.'
            )
            reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            pmd_root = "-"
        elseif
            (musictheory.root_table[string.sub(value[4], 1, 1)] == nil and string.sub(value[4], 1, 1) ~= "b" and
                string.sub(value[4], 1, 1) ~= "#")
         then
            --   																					ACTUAL NORMAL CHORD SITUATIONS
            -- MISSING SOMETHING HERE?  WORRIED ALL CASES NOT COVERED
            pmd_error_log = -- SPECIAL CASE DETECTED
                pmd_error_log ..
                "Found special case where " .. string.sub(value[4], 1, 1) .. " has been used." .. string.char(10)
            pmd_note_end_ppqpos = pmd_running_ppqpos_total + 0
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
            marker_name_from_value4 = value[4], 3, -2
            table.insert(G_region_table, {pmd_running_ppqpos_total, marker_name_from_value4})

			if chord_table[i + 1] ~= nil then 
			next_records_value_4 = chord_table[i + 1][4]
			next_records_value_3 = chord_table[i + 1][3]
			user_left_section_empty = false
			else
			user_left_section_empty = true   
			end
			

			

			
			if next_records_value_4 == nil or string.sub(next_records_value_4, 1,2) == "{$" or chord_table[i + 1] == nil then
				user_left_section_empty = true
			else
				user_left_section_empty = false          

			end
			


			

            if string.sub(next_records_value_4, 1, 1) == "-" then
                pmd_note_end_ppqpos = pmd_running_ppqpos_total
                pmd_running_ppqpos_total = pmd_note_end_ppqpos
                text_item_color = reaper.ColorToNative(133, 133, 133) | 0x1000000
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            elseif
                (string.sub(next_records_value_4, 1, 1) == "b" and
                    musictheory.root_table[string.sub(next_records_value_4, 1, 2)] == nil)
             then
                pmd_error_log =
                    pmd_error_log ..
                    "Invalid flat root " .. string.sub(next_records_value_4, 1, 2) .. " used." .. string.char(10)
                text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
                reaper.ULT_SetMediaItemNote(
                    pmd_item_to_color,
                    '!!! ENTRY ERROR !!! \n"' ..
                        string.sub(next_records_value_4, 1, 2) .. '" \nis not a supported chord root.'
                )
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
                pmd_root = "-"
            elseif
                (string.sub(next_records_value_4, 1, 1) == "#" and
                    musictheory.root_table[string.sub(next_records_value_4, 1, 2)] == nil)
             then
                pmd_error_log =
                    pmd_error_log ..
                    "Invalid sharp root " .. string.sub(next_records_value_4, 1, 2) .. " used." .. string.char(10)
                pmd_note_end_ppqpos = pmd_running_ppqpos_total + next_records_value_3
                pmd_running_ppqpos_total = pmd_note_end_ppqpos
                text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
                reaper.ULT_SetMediaItemNote(
                    pmd_item_to_color,
                    '!!! ENTRY ERROR !!! \n"' ..
                        string.sub(next_records_value_4, 1, 2) .. '" \nis not a supported chord root.'
                )
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
                pmd_root = "-"
            elseif
                (musictheory.root_table[string.sub(next_records_value_4, 1, 1)] == nil and
                    string.sub(next_records_value_4, 1, 1) ~= "{" and
                    string.sub(next_records_value_4, 1, 1) ~= "b" and
                    string.sub(next_records_value_4, 1, 1) ~= "#")
             then
                --   																					I HAVE LOST TRACK OF WHAT THIS SITUATION IS...
                pmd_error_log =
                    pmd_error_log ..
                    "Invalid root character " .. string.sub(next_records_value_4, 1, 1) .. " used." .. string.char(10)
                pmd_note_end_ppqpos = pmd_running_ppqpos_total + next_records_value_3
                pmd_running_ppqpos_total = pmd_note_end_ppqpos
                text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
                reaper.ULT_SetMediaItemNote(
                    pmd_item_to_color,
                    '!!! ENTRY ERROR !!! \n"' ..
                        string.sub(next_records_value_4, 1, 1) .. '" \nis not a supported chord root.'
                )
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
                pmd_root = "-"
            elseif string.sub(next_records_value_4, 1, 1) == "b" or string.sub(next_records_value_4, 1, 1) == "#" then
                pmd_root = musictheory.root_table[string.sub(next_records_value_4, 1, 2)]
                chord_type = string.sub(next_records_value_4, 3, string.len(next_records_value_4))
                color_table = musictheory.root_colors[string.sub(next_records_value_4, 1, 2)]
                text_item_color = reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            else
                pmd_root = musictheory.root_table[string.sub(next_records_value_4, 1, 1)]
                chord_type = string.sub(next_records_value_4, 2, string.len(next_records_value_4))
                color_table = musictheory.root_colors[string.sub(next_records_value_4, 1, 1)]
				--reaper.ShowConsoleMsg(next_records_value_4.."\n")
				if user_left_section_empty == false then
                text_item_color = reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
				else
				render_feedback = render_feedback .. "\nMinor error. Don't enter sections with no chords...\n" .. 'Remove the empty section(s) from either the "Form:" field or from the\nChord entry area and re-render.\n\n'
				end
            end
        else

            if string.sub(value[4], 1, 1) == "b" or string.sub(value[4], 1, 1) == "#" then
                pmd_root = musictheory.root_table[string.sub(value[4], 1, 2)]
                chord_type = string.sub(value[4], 3, string.len(value[4]))
                color_table = musictheory.root_colors[string.sub(value[4], 1, 2)]
                text_item_color = reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            else
                pmd_root = musictheory.root_table[string.sub(value[4], 1, 1)]
                chord_type = string.sub(value[4], 2, string.len(value[4]))
                color_table = musictheory.root_colors[string.sub(value[4], 1, 1)]
                text_item_color = reaper.ColorToNative(color_table[1], color_table[2], color_table[3]) | 0x1000000
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
            end
            if string.find(chord_type, "/") then
                pmd_error_log = pmd_error_log .. "found " .. string.char(10)
                slash_st_pos, slash_end_pos = string.find(chord_type, "/")
                if slash_st_pos == 1 then
                    bass_note_key = string.sub(chord_type, 2, string.len(chord_type))
                    chord_type = "z"
                else
                    string_original_lenght = string.len(chord_type)
                    bass_note_key = string.sub(chord_type, slash_end_pos + 1, string.len(chord_type))
                    chord_type = string.sub(chord_type, 1, slash_end_pos - 1)
                end
                bass_note = musictheory.root_table[bass_note_key]
                pmd_error_log = pmd_error_log .. "len = " .. string.len(chord_type) .. string.char(10)
                pmd_error_log =
                    pmd_error_log ..
                    "slash_st_pos = " .. slash_st_pos .. " slash_end_pos = " .. slash_end_pos .. string.char(10)
                pmd_error_log =
                    pmd_error_log ..
                    "chordtype = " .. chord_type .. " bass_note_key = " .. bass_note_key .. string.char(10)
                --pmd_error_log = pmd_error_log .. bass_note .. string.char(10)
                bass_note = musictheory.root_table[bass_note_key]
            else
                bass_note = pmd_root
            end

            if chord_type == "" then
                chord_type = "z"
            end

            --   																					GOOD PLACE FOR THE EFFECT OF THE KEY CHANGE

            if musictheory.key_table[current_key] == nil then
                --Show_To_Dev("Invalid Key " .. current_key .. " used." .. string.char(10))
                pmd_error_log = pmd_error_log .. "Invalid Key " .. current_key .. " used." .. string.char(10)
            else
                keyshift = musictheory.key_table[current_key]
                pmd_root = pmd_root + keyshift
                bass_note = bass_note + keyshift
                if pmd_root > 12 then
                    pmd_root = pmd_root - 12
                end
                if bass_note > 12 then
                    bass_note = bass_note - 12
                end
            end

            --   																					END THE KEY CHANGE

            --lead_item = reaper.GetMediaItem(0, 0)
            lead_item_first_take = reaper.GetMediaItemTake(pmd_lead_midi_item_id, 0)
            --chord_item = reaper.GetMediaItem(0, 1)
            chord_item_first_take = reaper.GetMediaItemTake(pmd_chords_midi_item_id, 0)
            --bass_item = reaper.GetMediaItem(0, 2)
            bass_item_first_take = reaper.GetMediaItemTake(pmd_bass_midi_item_id, 0)
            --chord_and_bass_item = reaper.GetMediaItem(0, 3)
            chbass_item_first_take = reaper.GetMediaItemTake(pmd_chbass_midi_item_id, 0)
            --bass_item = reaper.GetMediaItem(0, 4)
            grid_item_first_take = reaper.GetMediaItemTake(pmd_grid_midi_item_id, 0)

            pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
            tiny_table_of_chord_tones = musictheory.type_table[chord_type]
            last_pitch_total = pitch_total
            pitch_total = 0
            if tiny_table_of_chord_tones == nil then
                pmd_error_log =
                    pmd_error_log ..
                    "The chord type: " .. chord_type .. " was not found in the chord database." .. string.char(10)

                text_item_color = reaper.ColorToNative(0, 0, 0) | 0x1000000
                reaper.ULT_SetMediaItemNote(
                    pmd_item_to_color,
                    '!!! ENTRY ERROR !!! \n"' .. chord_type .. '" \nis not a supported chord type.'
                )
                reaper.SetMediaItemInfo_Value(pmd_item_to_color, "I_CUSTOMCOLOR", text_item_color)
                pmd_root = "-"
                pmd_note_end_ppqpos = pmd_running_ppqpos_total + value[3]
                pmd_running_ppqpos_total = pmd_note_end_ppqpos
            else
                for i, v in pairs(tiny_table_of_chord_tones) do
                    if v + pmd_root > 10 then
                        reaper.MIDI_InsertNote(
                            chord_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v - 12,
                            80
                        )
                        reaper.MIDI_InsertNote(
                            grid_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v - 12,
                            80
                        )
                        reaper.MIDI_InsertNote(
                            chbass_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v - 12,
                            80
                        )
                        if v == 0 then
                            reaper.MIDI_InsertNote(
                                bass_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 36,
                                80
                            )
                            reaper.MIDI_InsertNote(
                                grid_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 36,
                                80
                            )
                            reaper.MIDI_InsertNote(
                                chbass_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 36,
                                80
                            )
                        end
                    else
                        reaper.MIDI_InsertNote(
                            chord_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v,
                            80
                        )
                        reaper.MIDI_InsertNote(
                            grid_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v,
                            80
                        )
                        reaper.MIDI_InsertNote(
                            chbass_item_first_take,
                            0,
                            0,
                            pmd_running_ppqpos_total,
                            pmd_note_end_ppqpos,
                            16,
                            60 + pmd_root + v,
                            80
                        )
                        if v == 0 then
                            reaper.MIDI_InsertNote(
                                bass_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 24,
                                80
                            )
                            reaper.MIDI_InsertNote(
                                grid_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 24,
                                80
                            )
                            reaper.MIDI_InsertNote(
                                chbass_item_first_take,
                                0,
                                0,
                                pmd_running_ppqpos_total,
                                pmd_note_end_ppqpos,
                                16,
                                60 + bass_note + v - 24,
                                80
                            )
                        end
                    end
                end
            end
            pmd_running_ppqpos_total = pmd_note_end_ppqpos
        end
    end
    return pmd_error_log, pmd_running_ppqpos_total, grid_item_first_take
end

function place_special()
    num_regions = reaper.CountProjectMarkers(0)
    for i = num_regions, 0, -1 do
        reaper.DeleteProjectMarkerByIndex(0, i)
    end

    --Show_To_Dev("markers deleted")

    for i, v in pairs(G_region_table) do
        if G_region_table[i + 1] == nil then
            region_end = reaper.TimeMap2_beatsToTime(0, final_ppqpos_total / 960)
        else
            region_end = reaper.TimeMap2_beatsToTime(0, G_region_table[i + 1][1] / 960)
        end

        the_regions_name = string.sub(v[2], 3, (string.len(v[2])) - 2)

        region_item_color = reaper.ColorToNative(80, 80, 100) | 0x1000000
        if form.sections_colors[the_regions_name] == nil then
            region_item_color = reaper.ColorToNative(80, 80, 100) | 0x1000000
        else
            the_color_values = form.sections_colors[the_regions_name]
            --Show_To_Dev("  Color 1 " .. the_color_values[1] .. "  Color 2 " .. the_color_values[2] .. "  Color 3 " .. the_color_values[3] ..  string.char(10))
            region_item_color =
                reaper.ColorToNative(the_color_values[1], the_color_values[2], the_color_values[3]) | 0x1000000
        end

        starts_position = reaper.TimeMap2_beatsToTime(0, v[1] / 960)

        --Show_To_Dev("V1: " .. v[1] .. " V2: " .. the_regions_name .. " color int " .. region_item_color  .. string.char(10))
        reaper.AddProjectMarker2(0, true, starts_position, region_end, the_regions_name, i - 1, region_item_color)
        --reaper.AddProjectMarker2(ReaProject proj, boolean isrgn, number pos, number rgnend, string name, integer wantidx, integer color)
    end
    num_regions = 0
    G_region_table = {}
    starts_position = 0
    region_item_color = reaper.ColorToNative(80, 80, 100) | 0x1000000
    the_regions_name = ""
    region_end = 0
end
goopy = 0

function process_pushes()
    pushy_chord_table = chord_table
    for i, v in pairs(chord_table) do
        last_element = i
    end
    push_grab = 0
    for i = last_element, 1, -1 do
        chord_table[i][3] = chord_table[i][3] - push_grab
        if string.sub(chord_table[i][4], 1, 2) == "<." then
            --reaper.ShowConsoleMsg("Dottend 8th Push - " .. chord_table[i][4] .. "\n")
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            push_grab = 3 * (G_ticks_per_measure / 4)
        elseif string.sub(chord_table[i][4], 1, 3) == "2t<" or string.sub(chord_table[i][4], 1, 3) == "2T<" then
            --reaper.ShowConsoleMsg("Two Triplet Push - " .. chord_table[i][4] .. "\n")
            chord_table[i][4] = string.sub(chord_table[i][4], 4, string.len(chord_table[i][4]))
            push_grab = 2 * (G_ticks_per_measure / 3)
        elseif string.sub(chord_table[i][4], 1, 2) == "t<" or string.sub(chord_table[i][4], 1, 2) == "T<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Triplet Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 3
        elseif string.sub(chord_table[i][4], 1, 2) == "<<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 3, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Sixteenth Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 4
        elseif string.sub(chord_table[i][4], 1, 1) == "<" then
            chord_table[i][4] = string.sub(chord_table[i][4], 2, string.len(chord_table[i][4]))
            --reaper.ShowConsoleMsg("Eighth Push - " .. chord_table[i][4] .. "\n")
            push_grab = G_ticks_per_measure / 2
        else
            push_grab = 0
        end
        chord_table[i][3] = chord_table[i][3] + push_grab
    end
end

function chords_to_onemotion()
    local is_synco_found = false
    local the_absolute_chord = ""
    local om_root = ""
    local om_type_start = 0
    onemotionoutput = ""
    local om_notice = ""
    local ombeats = 0
    for i, value in pairs(chord_table) do
		--reaper.ShowConsoleMsg(value[4].."\n")
        if string.sub(value[4], 1, 2) == "{$" then
            om_marker = string.sub(value[4], 3, string.len(value[4]) - 2)

            onemotionoutput = onemotionoutput .. "<" .. om_marker .. "> "
        elseif string.sub(value[4], 1, 1) == "-" then
			reaper.ShowConsoleMsg('ei 1 = ' .. value[1].. ' 2 = ' .. value[2] .. ' 3 = ' .. (value[3])/960 .. ' 4 = ' .. value[4] ..'\n')
            ombeats = math.floor(value[3] / G_ticks_per_measure)
            if ombeats ~= (value[3] / G_ticks_per_measure) then
                if is_synco_found == false then
                    om_notice =
                        "Notice! - Onemotion.com does not handle off-beat chord changes." ..
                        string.char(10) ..
                            "Chord changes rounded to nearest beat!" ..
                                string.char(10) ..
                                    "_________________________________________________________________" ..
                                        string.char(10) .. string.char(10)
                    is_synco_found = true
                else
                end
            end

            onemotionoutput = onemotionoutput .. ombeats .. "rest default "
        else
            --k = 0
            --for k, v in pairs(value) do
            --    datapeek = datapeek .. " k = " .. k .. " / value = " .. v .. string.char(10)
            --end
            ombeats = math.floor(value[3] / G_ticks_per_measure)
			reaper.ShowConsoleMsg('e 1 = ' .. value[1].. ' 2 = ' .. value[2] .. ' 3 = ' .. (value[3])/960 .. ' 4 = ' .. value[4] ..'\n')
            if ombeats ~= (value[3] / G_ticks_per_measure) then
                if is_synco_found == false then
                    om_notice =
                        "Notice! - Onemotion.com does not handle off-beat chord changes." ..
                        string.char(10) ..
                            "Chord changes rounded to nearest beat!" ..
                                string.char(10) ..
                                    "_________________________________________________________________" ..
                                        string.char(10) .. string.char(10)
                    is_synco_found = true
                end
            end

            if ombeats == 0 then
                ombeats = 1
            end
            if string.sub(value[4], 1, 1) == "b" or string.sub(value[4], 1, 1) == "#" then
                om_root = string.sub(value[4], 1, 2)
                om_type_start = 3
            else
                om_root = string.sub(value[4], 1, 1)
                om_type_start = 2
            end
			current_key = set_the_key(header_area)
			current_key_shift = musictheory.key_table[current_key]

            local the_om_key_index = musictheory.root_table[om_root]
            if the_om_key_index == nil then
                --Show_To_Dev("!!!!!!!!!!!!!!!!!!!!! " .. om_root .. string.char(10))
            elseif the_om_key_index + current_key_shift < 0 then
                the_om_key_index = the_om_key_index + current_key_shift + 12
            elseif the_om_key_index + current_key_shift > 24 then
                the_om_key_index = the_om_key_index + current_key_shift - 24
            elseif the_om_key_index + current_key_shift >= 12 then
                the_om_key_index = the_om_key_index + current_key_shift - 12
			else
                the_om_key_index = the_om_key_index + current_key_shift		
			
            end

			--reaper.ShowConsoleMsg(the_om_key_index.."\n")
            if musictheory.is_it_flat_table[current_key] == true then
                the_absolute_chord = musictheory.flats_table[the_om_key_index]
            else
                the_absolute_chord = musictheory.sharps_table[the_om_key_index]
            end
            if string.sub(value[4], om_type_start, string.len(value[4])) == "" then
                onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. " "
            else


				om_slash_start_pos, _ = string.find(value[4],"/")
				if om_slash_start_pos ~= nil then
			reaper.ShowConsoleMsg("found one\n")
			type_end_pos = om_slash_start_pos - 1
			else
			
			type_end_pos = string.len(value[4])
				end

                onemotion_chord_type =
                    musictheory.to_onemotion_translation[string.sub(value[4], om_type_start, type_end_pos)]






                if onemotion_chord_type == nil then
					--reaper.ShowConsoleMsg("value was ".. value[4] .. "\n")
                    onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. " "

                else
						--reaper.ShowConsoleMsg(onemotion_chord_type.."\n")
                    onemotionoutput = onemotionoutput .. ombeats .. the_absolute_chord .. onemotion_chord_type .. " "
                end
            end
        end
    end
    reaper.ImGui_SetClipboardText(ctx, onemotionoutput)
    onemotionoutput = om_notice .. onemotionoutput
end






function render_all()
	
    reaper.ClearConsole() -- 			CLEAR THE CONSOLE
	

	Autosave()

	
	
	thetime = os.date('%Y-%m-%d %H-%M-%S')
	render_feedback = render_feedback .. "Rendered at " .. thetime .."\n"
    reaper.PreventUIRefresh(1)

    chord_charting_area = inital_swaps(chord_charting_area)
    G_track_list, G_track_table = Setup_Tracks() -- 260 		--SET UP TRACKS

    unfolded_user_data, error_zone = form.process_the_form(header_area, chord_charting_area) -- FORM		 DEAL WITH UNFOLDING THE FORM
    progression = Set_The_Current_Simulated_Userinput_Data(unfolded_user_data) -- 388 		SET INITIAL SIMULATED USER INPUT
    --Show_To_Dev("Charting Area = " .. string.char(10) .. chord_charting_area .. string.char(10))
    current_key = set_the_key(header_area)
    current_bpm = set_the_bpm(header_area)
	set_the_swing(header_area)
    G_split, G_error_log = orgainize_input_into_bars(G_error_log) -- 395 		ORGANIZE BARS
    --presentdata(G_split, G_error_log)
    G_split, G_error_log = process_nested_split_sections(G_split, G_error_log) -- 620 		PROCESS SPLIT CHORDS
    --presentdata(G_split, G_error_log)
    -- 662 		PLACE THE TEXT ITEMS IN TRACKS

    process_pushes()
    presentdata(G_split, G_error_log)
    G_text_item_count,
        G_lead_midi_item_id,
        G_chords_midi_item_id,
        G_bass_midi_item_id,
        G_chbass_midi_item_id,
        G_grid_midi_item_id = place_TEXT_data(G_track_table)

    -- 743 		PLACE THE MIDI ITEMS IN TRACKS

    _, final_ppqpos_total, G_grid_item_first_take =
        place_MIDI_data(
        G_text_item_count,
        G_lead_midi_item_id,
        G_chords_midi_item_id,
        G_bass_midi_item_id,
        G_chbass_midi_item_id,
        G_grid_midi_item_id,
        G_track_table
    )

    place_special()

    ----Show_To_Dev(moops)
    notneeded = spectrum.make_full_spectrum(G_grid_item_first_take)

    close_all_fx_windows = reaper.NamedCommandLookup("_S&M_WNCLS3") -- CLOSE 	FX WINDOWS ON 1st OPEN
    reaper.Main_OnCommand(close_all_fx_windows, 0)
    -- RESET 	VARIABLES FOR NEXT RUN
    G_split = 0
    G_error_log = "START ERROR LOG - " .. string.char(10)
    G_time_signature_top = 4
    G_ticks_per_measure = 960

    inparenthetical = false
    chord_table = {}
    temp_chord_table = {}
    updated_chord_table = {}

    chord_splitsection_count = 0
    temp_chord_splitsection_count = 0
    updated_chord_splitsection_count = 0

    reaper.PreventUIRefresh(-1)
    modal_on = false
end



function import_onemotion()
    reaper.PreventUIRefresh(1)
    local omi_key = "G"
    local omi_conversion_table = {}
    local omi_beats = 0
    local omi_root = ""
    local omi_type = ""
    local omi_inmarker = false
    local omi_import_text = ""
    local omi_inchord = false
    local omi_chord = ""
    local omi_chord_table = {}
    local omi_parsed_table = {}
    local chord_count = 0
    onemotionimport = ""
    omi_import_text = reaper.CF_GetClipboard()

    if
        string.len(omi_import_text) == 0 or string.len(omi_import_text) == nil or
            musictheory.key_table[import_key] == nil
     then
        onemotionimport =
            'Make sure you have copied the "Edit All" data from Onemotion.com Chord \nPlayer and set the Import Key before attempting conversion.'
    else
        --omi_import_text = "<Intro> 2G5 2Gadd9 4Bsus4 4C 4Dadd9 <Verse 1> 4G5 4Gadd9 4Bsus4 4C 4Dadd9 1Ebm 1Rest 1Em 1C 2D 6Em 4Em 4C#m 4D 4Em 4Em 4C 4C 4C 4D"
        local swaptext = string.gsub(omi_import_text, "4onlyBass", "")
        omi_import_text = string.gsub(swaptext, "onlyBass", "")
        swaptext = string.gsub(omi_import_text, "4onlyChord", "")
        omi_import_text = string.gsub(swaptext, "onlyChord", "")
        swaptext = string.gsub(omi_import_text, "default", "")
        omi_import_text = swaptext

        --Show_To_Dev("start inport" .. string.char(10) .. omi_import_text .. string.char(10) )

        for i = 1, string.len(omi_import_text), 1 do
            -- USELESS SPACE
            if string.sub(omi_import_text, i, i) == " " and omi_inchord == false and omi_inmarker == false then
                -- SPACE THAT CAPS OFF A CHORD OR MARKER
            elseif string.sub(omi_import_text, i, i) == " " and omi_inchord == true and omi_inmarker == false then
                -- SPACE IN THE MIDDLE OF A MARKER
                chord_count = chord_count + 1
                table.insert(omi_chord_table, chord_count, omi_chord)
                --Show_To_Dev("omichord = " .. omi_chord .. string.char(10) )
                omi_inmarker = false
                omi_inchord = false
                omi_chord = ""
            elseif string.sub(omi_import_text, i, i) == " " and omi_inmarker == true and omi_inchord == false then
                -- "<" TRIGGERING START OF A MARKER
                omi_inchord = false
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            elseif string.sub(omi_import_text, i, i) == "<" then
                -- ">" TRIGGERING END OF A MARKER
                omi_inchord = false
                omi_inmarker = true
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            elseif string.sub(omi_import_text, i, i) == ">" then
                -- OTHER CHARACTERS IN THE MIDDLE OF A CHORD
                omi_inmarker = false
                omi_inchord = true
            else
                if omi_inmarker == false then
					omi_inchord = true
                end
                omi_chord = omi_chord .. string.sub(omi_import_text, i, i)
            end
        end
        if omi_inchord == true then
            chord_count = chord_count + 1
            table.insert(omi_chord_table, chord_count, omi_chord)
            --Show_To_Dev("omichord = " .. omi_chord .. string.char(10) )
            omi_inchord = false
            omi_chord = ""
        end
        for i, v in pairs(omi_chord_table) do
            --Show_To_Dev(v .. string.char(10))
            onemotionimport = onemotionimport .. v .. string.char(10)
            local beatcountlen = 0
            alldone = false
            for j = 1, string.len(v), 1 do
                if tonumber(string.sub(v, j, j)) ~= nil and alldone == false then
                    beatcountlen = beatcountlen + 1
                else
                    alldone = true
                end
            end
            if beatcountlen > 0 then
                --Show_To_Dev("number of beats = " .. string.sub(v, 1, beatcountlen) .. " ")
                omi_beats = string.sub(v, 1, beatcountlen)
                if string.sub(v, beatcountlen + 1, string.len(v)) == "Rest" then
                    --Show_To_Dev("type = Rest" .. string.char(10) )
                    omi_root = "-"
                    final_omi_numeric_root = omi_root
                    omi_real_root = false
                    omi_type = ""
                elseif
                    string.sub(v, beatcountlen + 2, beatcountlen + 2) == "#" or
                        string.sub(v, beatcountlen + 2, beatcountlen + 2) == "b"
                 then
                    omi_root = string.sub(v, beatcountlen + 1, beatcountlen + 2)
                    omi_real_root = true
                    --Show_To_Dev("root = " .. string.sub(v, beatcountlen + 1, beatcountlen + 2) .. " " )

                    if beatcountlen + 3 > string.len(v) then
                        --Show_To_Dev("type = " .. string.char(10) )
                        omi_type = ""
                    else
                        --Show_To_Dev("type = " .. musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 3, string.len(v))] .. string.char(10) )
                        omi_type =
                            musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 3, string.len(v))]
                    end
                else
                    omi_root = string.sub(v, beatcountlen + 1, beatcountlen + 1)
                    omi_real_root = true
                    --Show_To_Dev("root = " .. string.sub(v, beatcountlen + 1, beatcountlen + 1) .. " " )
                    if beatcountlen + 2 > string.len(v) then
                        --Show_To_Dev("type = " .. string.char(10) )
                        omi_type = ""
                    else
                        --Show_To_Dev("type = " .. musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 2, string.len(v))] .. string.char(10) )
                        omi_type =
                            musictheory.from_onemotion_translation[string.sub(v, beatcountlen + 2, string.len(v))]
                    end
                end
            elseif beatcountlen == 0 and string.sub(v, 1, 1) == "<" then
                --Show_To_Dev("something else = " .. '>"' .. string.sub(v, 2, -1) .. '"}' .. string.char(10) )
                omi_beats = 0
                omi_root = '{"' .. string.sub(v, 2, -1) .. '"}'
                final_omi_numeric_root = omi_root
                omi_type = "marker"
                omi_real_root = false
            end
            if omi_real_root == true then
                omi_key_is_flat = musictheory.is_it_flat_table[omi_root]
                omi_root_value = musictheory.key_table[omi_root]
                omi_root_shift = musictheory.key_table[import_key]
                omi_combo_shift = omi_root_value - omi_root_shift
                if omi_combo_shift > 24 then
                    omi_combo_shift = omi_combo_shift - 24
                elseif omi_combo_shift > 12 then
                    omi_combo_shift = omi_combo_shift - 12
                elseif omi_combo_shift < 0 then
                    omi_combo_shift = omi_combo_shift + 12
                end
                --Show_To_Dev("root = " .. omi_root_value .. " shift value = " .. omi_root_shift .. " combo = " .. omi_combo_shift .. string.char(10))

                final_omi_numeric_root = musictheory.reverse_root_table[omi_combo_shift]
            end

            table.insert(omi_parsed_table, i, {omi_beats, final_omi_numeric_root, omi_type})

            onemotionimport =
                swaptext ..
                string.char(10) ..
                    "________________________________________________________________" ..
                        string.char(10) ..
                            "Imported Onemotion.com Chord Player progression from clipboard..." ..
                                string.char(10) ..
                                    "________________________________________________________________" ..
                                        string.char(10)
            oim_in_measure = false
            oim_beats_thus_far = 0
            oim_measures_in_clump = 0
            oim_measures_per_line = 0
            for i, v in pairs(omi_parsed_table) do
                oim_current_beats = tonumber(v[1])
                if oim_current_beats == 0 then
                    onemotionimport = onemotionimport .. string.char(10) .. string.char(10) .. v[2] .. string.char(10)
                else
                    ::doagain::
                    if oim_beats_thus_far == 0 and oim_current_beats > 0 then
                        if oim_current_beats > 4 then
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t"
                            else
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t" .. string.char(10)
                                oim_measures_per_line = 0
                            end
                            oim_current_beats = oim_current_beats - 4
                            goto doagain
                        elseif oim_current_beats == 4 then
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t"
                            else
                                onemotionimport = onemotionimport .. v[2] .. v[3] .. "\t\t\t\t" .. string.char(10)
                                oim_measures_per_line = 0
                            end
                            oim_current_beats = 0
                        elseif oim_current_beats < 4 then
                            onemotionimport = onemotionimport .. "[" .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                            oim_beats_thus_far = oim_current_beats
                        end
                    elseif oim_beats_thus_far + oim_current_beats < 4 then
                        oim_beats_thus_far = oim_current_beats + oim_beats_thus_far
                        onemotionimport = onemotionimport .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                    elseif oim_beats_thus_far + oim_current_beats == 4 then
                        oim_beats_thus_far = 0
                        onemotionimport = onemotionimport .. oim_current_beats .. "(" .. v[2] .. v[3] .. ") "
                        oim_measures_per_line = oim_measures_per_line + 1
                        if oim_measures_per_line < 4 then
                            onemotionimport = onemotionimport .. "]\t\t\t"
                        else
                            onemotionimport = onemotionimport .. "]\t\t\t" .. string.char(10)
                            oim_measures_per_line = 0
                        end
                        oim_current_beats = 0
                    else
                        if oim_beats_thus_far + oim_current_beats > 4 then
                            needed_beats = 4 - oim_beats_thus_far
                            oim_measures_per_line = oim_measures_per_line + 1
                            if oim_measures_per_line < 4 then
                                onemotionimport = onemotionimport .. needed_beats .. "(" .. v[2] .. v[3] .. ")]\t\t"
                            else
                                onemotionimport =
                                    onemotionimport .. needed_beats .. "(" .. v[2] .. v[3] .. ")]" .. string.char(10)
                            end

                            oim_current_beats = oim_current_beats - needed_beats
                            oim_beats_thus_far = 0
                            goto doagain
                        end
                    end
                end
            end
        end
    end

    --reaper.ImGui_SetClipboardText(ctx, onemotionimport)
    reaper.PreventUIRefresh(-1)
end

function letters_to_numbers(keysig, letters)
    reaper.PreventUIRefresh(1) -- turn off screen updates so script can go faster
    if musictheory.is_it_flat_table[keysig] ~= nil then -- double check a valid major key has been entered
        numbers_result = letters
        for k, v in pairs(musictheory.conflict_table) do -- temporarily replace chords name parts with musical alphabet letters like add2 so no confusion with A or D chords
            numbers_result = string.gsub(numbers_result, k, v)
        end
        key_number = musictheory.key_table[keysig] -- for example in Ab key_number = 8
        for i, v in pairs(musictheory.full_letter_list_set) do
            currentletter = v[1] -- go through every possible musical alphabet letter name ie, A, A#, Ab etc.
            --reaper.ShowConsoleMsg(currentletter.."\n")
            shifted_key_number = v[2] - key_number -- letter shift from C
            --reaper.ShowConsoleMsg("v[2] = " .. v[2].. " - key number " .. key_number .. " = " .. shifted_key_number .. "\n")
            if v[2] - key_number < 0 then
                shifted_key_number = (v[2] - key_number) + 12
            end -- shift up an octave if needed
            replacing_number = musictheory.reverse_root_table[shifted_key_number] -- look up the numeric root now that the key shift and individual note shift are known
            numbers_result = string.gsub(numbers_result, currentletter, replacing_number) -- swap out the name (like C) for the number (like 1)
        end
        for k, v in pairs(musictheory.reverse_conflict_table) do
            numbers_result = string.gsub(numbers_result, k, v) -- put back the chords name parts with musical alphabet letters like add2
        end
        ::tidy::
        slenght = string.len(numbers_result)
        numbers_result = string.gsub(numbers_result, "  ", " ")
        numbers_result = string.gsub(numbers_result, string.char(10) .. " ", string.char(10))
        if string.len(numbers_result) ~= slenght then
            goto tidy
        end
        slenght = string.len(numbers_result)
        numbers_result = string.gsub(numbers_result, " ", "    ")
    else
        numbers_result =
            "You must first enter a valid key signature.\nUse a major key!\n\nWhen the key is minor, Nashville Numbers generally indicate the \nrelative minor and focus on 6m as the key center."
    end
    reaper.PreventUIRefresh(-1)
    return numbers_result
end
function play_button_midi(v_in, play_root_in)
    local audition_key = set_the_key(header_area)
    audition_key_shift = musictheory.key_table[audition_key]
    if r.ImGui_Button(ctx, play_root_in .. v_in[2], wx, hx) then
        if v_in[1] == "" then
            this_type = "z"
        else
            this_type = v_in[1]
        end
        down_key_check = reaper.ImGui_GetKeyMods(ctx)
        if down_key_check == 1 or down_key_check == 3 then
            chord_charting_area = chord_charting_area .. play_root_in .. v_in[2] .. "  "
        end
        for i, v in pairs(current_playing_tone_array) do
            reaper.StuffMIDIMessage(0, 128, 48 + v + musictheory.root_table[last_play_root] + audition_key_shift, 111)
        end
        current_playing_tone_array = musictheory.type_table[this_type]
        if liveMIDI_playing_timer == 0 then
            for i, v in pairs(current_playing_tone_array) do
                reaper.SetMediaTrackInfo_Value(audition_track, "B_MUTE", 0)
                reaper.StuffMIDIMessage(0, 144, 48 + v + musictheory.root_table[play_root_in] + audition_key_shift, 111)
                last_play_root = play_root_in
            end
            liveMIDI_playing_timer = 24
        end
    end
end

function SetVMidiInput(chan, dev_name)
    trac_count = reaper.CountTracks(0)
    --reaper.ShowConsoleMsg(trac_count)
    for i = 0, trac_count - 1, 1 do
        trac_id = reaper.GetTrack(0, i)
        yeahnothing, trac_name = reaper.GetTrackName(trac_id)
        if trac_name == "N2N Audition" then
            local tr = trac_id
            if not tr then
                return
            end
            for i = 0, 64 do
                local retval, nameout = reaper.GetMIDIInputName(i, "")
                if nameout:lower():match(dev_name:lower()) then
                    dev_id = i
                end
            end
            if not dev_id then
                return
            end
            val = 4096 + chan + (dev_id << 5)
            reaper.SetMediaTrackInfo_Value(tr, "I_RECARM", 1)
            reaper.SetMediaTrackInfo_Value(tr, "I_RECMODE", 2)
            reaper.SetMediaTrackInfo_Value(tr, "B_MUTE", 1)
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINTCP", 0)
            reaper.SetMediaTrackInfo_Value(tr, "B_SHOWINMIXER", 0)			
            reaper.SetMediaTrackInfo_Value(tr, "I_RECINPUT", val)
            audition_track = tr
        --reaper.ShowConsoleMsg(tostring(audition_track))
        end
    end
end



















function Export_OM()
	OM_ex_warning = ""
	reaper.PreventUIRefresh(1)
	the_last_ccc_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
	_, ckey_startso  = string.find(header_area, "Key: ")
	ckey_endso, _  = string.find(header_area, "Swing:")
	_, cbpm_startso  = string.find(header_area, "BPM: ")
	cbpm_endso, _  = string.find(header_area, "Key:")
	cbpmfound = string.sub(header_area, cbpm_startso+1, cbpm_endso-2)
	ckeyfound = string.sub(header_area, ckey_startso+1, ckey_endso-2)
	theresultofprocessOMbars = Process_OM_bars()
	--if cancel_OM_opperation == true then
	--	onemotionoutput = the_OM_fail
--	else
		onemotionoutput = theresultofprocessOMbars
	--end
	reaper.PreventUIRefresh(-1)
end

-- ==============================================================================





---------------------------------------------------------Chordsheet Com Create SUB FOR PROCESSESSING ALL THE BARS
-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\

function Process_OM_bars()
local processmore_OM_table = {}
local insubdepth = 0
local inmeasurenow = false		-- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
cancel_OM_opperation = false
the_OM_fail = ""
OM_ex_warning = ""
measurechord_count = 0
OM_rebuild = ""
unfolded_OM_data, error_zone = form.process_the_form(header_area, chord_charting_area) 
unfolded_OM_data = inital_swaps(unfolded_OM_data)

--make chord list protected by swaping chord for &chord&
OM_swaplist = {
{"<<","~"},
{",","  "},
{";","  "},
{"%^%^","~"},
{"%^"," <"},
{"%$",""},
{"\n","  "},
{"\t","  "},
{"  "," "},
{"%]%[","] ["},
{"%[ " , "["},
{" %]" , "]"},
{" %- " , " $r$ "},
{" R " , " $r$ "},
{" r " , " $r$ "},
{"%( " , "("},
{"%)  " , ") "},
{" %)" , ")"},
{"J" , "majorJ"},
{"majorJ","j"},
{"Maj" , "major"},
{"MAJ" , "major"},
{"major" , "maj"},
{"Sus" , "sustained"},
{"SUS" , "sustained"},
{"sustained" , "sus"},
{"Add" , "Addition"},
{"ADD" , "Addition"},
{"Addition" , "add"},
{"Aug" , "Augmented"},
{"AUG" , "Augmented"},
{"Augmented" , "aug"},
{"Dim" , "diminished"},
{"DIM" , "diminished"},
{"diminished" , "dim"},
{"Hdim","hdim"},
{"HDIM","hdim"},
{"M" , "minor"},
{"minor" , "m"},


}


stuff_to_purge_from_chords = {
["A"]=1,
["B"]=1,
["C"]=1,
["D"]=1,
["E"]=1,
["F"]=1,
["G"]=1,
["I"]=1,
["K"]=1,
["L"]=1,
["M"]=1,
["N"]=1,
["O"]=1,
["P"]=1,
["Q"]=1,
["R"]=1,
["S"]=1,
["T"]=1,
["V"]=1,
["W"]=1,
["Y"]=1,
["Z"]=1,
["c"]=1,
["e"]=1,
["f"]=1,
["k"]=1,
["l"]=1,
["p"]=1,
["q"]=1,
["t"]=1,
["v"]=1,
["w"]=1,
["y"]=1,
["z"]=1,
["@"]=1,
["&"]=1,
["*"]=1,
['"']=1,
["'"]=1,
["`"]=1
}



unfolded_OM_data = string.gsub(unfolded_OM_data, "%)", ") ")
unfolded_OM_data = Swapout(unfolded_OM_data, OM_swaplist)

for i = 1,string.len(unfolded_OM_data) do
	if cancel_OM_opperation == true then
		the_OM_fail = 'Subdivision close ")" found without first being opened with "(".\n'
		cancel_OM_opperation = true
		break	
	elseif string.sub(unfolded_OM_data,i,i) == "{" and inmarker == true then  -- WARN WHEN THERE IS A {{ USER ERROR
		the_OM_fail = 'Don\'t use a "{" until you first close off the marker you are in.\n'
		cancel_OM_opperation = true
		break
	elseif string.sub(unfolded_OM_data,i,i) == "}" and inmarker == false then	 -- WARN WHEN THERE IS A LONE } USER ERROR
		the_OM_fail = 'Marker closer "}" found without a previous marker starter "{".\n'
		cancel_OM_opperation = true
		break
	elseif string.sub(unfolded_OM_data,i,i) == "{" and inmeasurenow == true then	 -- WARN WHEN THERE IS A { in measure USER ERROR
		the_OM_fail = 'You should not use "{" in the middle of a measure.\n'
		cancel_OM_opperation = true
		break	
	elseif string.sub(unfolded_OM_data,i,i) == "}" and inmeasurenow == true then	 -- WARN WHEN THERE IS A } in measure USER ERROR
		the_OM_fail = 'You should not use "}" in the middle of a measure.\n'
		cancel_OM_opperation = true
		break	
	elseif string.sub(unfolded_OM_data,i,i) == "[" and inmeasurenow == true then	 -- WARN WHEN THERE IS A ]] USER ERROR
		the_OM_fail = 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
		cancel_OM_opperation = true
		break	
	elseif string.sub(unfolded_OM_data,i,i) == "]" and inmeasurenow == false then  -- WARN WHEN THERE IS A [[ USER ERROR
		the_OM_fail = 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
		cancel_OM_opperation = true
		break
	elseif  string.sub(unfolded_OM_data,i,i) == "(" and inmeasurenow == false then   -- WARN WHEN THERE IS A ( in a measure USER ERROR
		the_OM_fail = 'Subdivisions marked with "(" should only occur in measure markers "[  ]".\n'
		cancel_OM_opperation = true
		break
	elseif  string.sub(unfolded_OM_data,i,i) == ")" and inmeasurenow == false then   -- WARN WHEN THERE IS A ) in a measure USER ERROR
		the_OM_fail = 'Subdivisions closings marked with ")" should only occur in within measure markers "[  ]".\n'
		cancel_OM_opperation = true
		break
	elseif  string.sub(unfolded_OM_data,i,i) == ")" and inmeasurenow == true  and inmarker == false then
		OM_rebuild = OM_rebuild .. ")"		-- CHANGE IN MEASURE SEPS TO COLON
		if insubdepth == 0 then
			the_OM_fail = 'Subdivision close ")" found without first being opened with "(".\n'
			cancel_OM_opperation = true
		else
			insubdepth = insubdepth - 1
		end
	elseif  string.sub(unfolded_OM_data,i,i) == "(" and inmeasurenow == true  and inmarker == false then
		OM_rebuild = OM_rebuild .. "("		-- CHANGE IN MEASURE SEPS TO COLON
		insubdepth = insubdepth + 1
	elseif insubdepth < 0 then	 -- WARN WHEN THERE IS A ]] USER ERROR
		the_OM_fail = the_OM_fail .. 'Incident of mismatched parentensis.  Make sure to use "(" and ")" in pairs.\n'
		cancel_OM_opperation = true
		break
	elseif string.sub(unfolded_OM_data,i,i) == "{" then
		inmarker = true
		OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data,i,i)			-- OM_rebuild WITH IN BRACE AS IS (UNLESS...)		
	elseif string.sub(unfolded_OM_data,i,i) == "}" then
		inmarker = false
		OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data,i,i)			-- OM_rebuild WITH IN BRACE AS IS (UNLESS...)				
	elseif string.sub(unfolded_OM_data,i,i) == "[" and inmeasurenow == false then
		inmeasurenow = true
		OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data,i,i)			-- OM_rebuild WITH IN BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_OM_data,i,i) == "]" and inmeasurenow == true then
		inmeasurenow = false
		OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data,i,i)			-- OM_rebuild WITH OUT BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_OM_data,i,i) == " " and inmeasurenow == false and inmarker == false and insubdepth == 0 then
		OM_rebuild = OM_rebuild .. ","													-- CHANGE MEASURE SEPARATORS TO COMMA
	elseif string.sub(unfolded_OM_data,i,i) == " " and inmeasurenow == true  and inmarker == false and insubdepth > 0  then
		OM_rebuild = OM_rebuild .. ";"
	elseif string.sub(unfolded_OM_data,i,i) == " " and inmeasurenow == true  and inmarker == false and insubdepth == 0 then
		OM_rebuild = OM_rebuild .. ":"													-- CHANGE IN MEASURE SEPS TO COLON		
	else
		OM_rebuild = OM_rebuild .. string.sub(unfolded_OM_data,i,i)						-- PASS EVERYTHING ELSE AS IS
	end
end

		inmarkernow = false
		OM_rebuild2 = ""
for i = 1,string.len(OM_rebuild) do
		current_singleOMchar = string.sub(OM_rebuild,i,i)
		if current_singleOMchar == "{" then
			inmarkernow = true
			OM_rebuild2 = OM_rebuild2 .. current_singleOMchar				
		elseif current_singleOMchar == "}" then
			inmarkernow = false
			OM_rebuild2 = OM_rebuild2 .. current_singleOMchar				
		elseif stuff_to_purge_from_chords[current_singleOMchar] == nil then
			OM_rebuild2 = OM_rebuild2 .. current_singleOMchar						-- PASS EVERYTHING ELSE AS IS
		elseif inmarkernow == true then
			OM_rebuild2 = OM_rebuild2 .. current_singleOMchar						-- PASS EVERYTHING ELSE AS IS		
		else
		end
end


	--reaper.ShowConsoleMsg(unfolded_OM_data.. "\n")
	--reaper.ShowConsoleMsg(OM_rebuild.. "\n")
	--reaper.ShowConsoleMsg("THE FAIL: " .. the_OM_fail.. "\n")	

OM_main_bars_table = Split(OM_rebuild2, ",")											-- PUT THE DATA INTO TABLE
OM_rebuild = ""        -- clear memory
OM_rebuild2 = ""        -- clear memory
unfolded_OM_data = ""        -- clear memory





-----
for iOM,vOM in pairs(OM_main_bars_table) do		--  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
	if vOM ~= nil and vOM ~= "" then
		if string.find(vOM, "%[") then
			processmore_OM_table[iOM] = {true,1}											-- TAG AS MULTIBAR IN this TABLE
		elseif string.find(vOM, "{") then
			processmore_OM_table[iOM] = {false,0}											-- A) SECTION HEADER - NOT A MEASURE
		else
			processmore_OM_table[iOM] = {false,1}	
			OM_main_bars_table[iOM] = OM_main_bars_table[iOM]   -- TAG AS A SINGLE BAR
		end
	end	
end
-----

-----------------
for iOMpm,vOMpm in pairs(processmore_OM_table) do	
	OM_start_brace_pos, _  = string.find(OM_main_bars_table[iOMpm], "%[")
	if OM_start_brace_pos ~=nil and OM_start_brace_pos > 1 then
		should_be_multiple = string.sub(OM_main_bars_table[iOMpm],1, OM_start_brace_pos - 1)
		if'number' == type(tonumber(should_be_multiple)) then
			processmore_OM_table[iOMpm][2] = tonumber(should_be_multiple)
			--reaper.ShowConsoleMsg(tostring(should_be_multiple) .. "\n")
		else
			processmore_OM_table[iOMpm][2] = 1
			the_OM_fail = the_OM_fail .. 'Only numbers should preceed the "[" symbol.'
		end
		OM_main_bars_table[iOMpm] = string.sub(OM_main_bars_table[iOMpm], OM_start_brace_pos + 1, string.len(OM_main_bars_table[iOMpm])-1)
	elseif OM_start_brace_pos ~=nil and OM_start_brace_pos == 1 then
		OM_main_bars_table[iOMpm] = string.sub(OM_main_bars_table[iOMpm], OM_start_brace_pos + 1, string.len(OM_main_bars_table[iOMpm])-1)
	end
	_, OM_bar_chord_count = string.gsub(OM_main_bars_table[iOMpm], ":", "")
	processmore_OM_table[iOMpm][3] = OM_bar_chord_count	+ 1
	processmore_OM_table[iOMpm][4] = Split(OM_main_bars_table[iOMpm], ":")
end

-----------------
cyclecount = 0
::run_an_unfolding_cycle::

nextlayer_table = {}
nextlayer_table_elem_count = 0
timesignature = 4
OMfalsesofar = 0
tablerecords = ""
chordchunk = {}
for i1, tablerecords in pairs(processmore_OM_table) do
	right_now_table = {}
	if tablerecords[1] == false and tablerecords[2] == 0 then   -- NO MEASURE MARKER ONLY
		-- COULD DO THE SECTION SWAPOUTS RIGHT HERE
		nextlayer_table_elem_count = nextlayer_table_elem_count + 1
		nextlayer_table[nextlayer_table_elem_count] = {processmore_OM_table[i1][1],processmore_OM_table[i1][2],nextlayer_table_elem_count,processmore_OM_table[i1][4]}
	elseif tablerecords[1] == false and tablerecords[2] > 0 then  -- SINGLE CHORD
		nextlayer_table_elem_count = nextlayer_table_elem_count + 1		
		nextlayer_table[nextlayer_table_elem_count] = {processmore_OM_table[i1][1],processmore_OM_table[i1][2],nextlayer_table_elem_count,processmore_OM_table[i1][4]}
	elseif tablerecords[1] == true then
		divtotal = 0
		for i2, chordchunk in pairs(tablerecords[4]) do			--  PROCESS EACH CHORD CHUNK
			--reaper.ShowConsoleMsg("chunk: " .. chordchunk .." -- \n")		
			start_pos_OM_par, _  = string.find(chordchunk, "%(")  -- LOOK IN THAT CHUNK FOR (
			if start_pos_OM_par ~= nil and type(tonumber(string.sub(chordchunk,1,start_pos_OM_par - 1))) == "number" then
				divmult =  tonumber(string.sub(chordchunk,1,start_pos_OM_par - 1))     --  FOUND ANOTHER DIGIT
				--reaper.ShowConsoleMsg("start_pos_OM_par " .. start_pos_OM_par .." -- \n")   -- SHOW WHERE
			elseif start_pos_OM_par ~= nil then              -- FOUND DIVISION MULTI THAT ISN'T A NUMBER
				divmult = 1
				local subdivOM = string.sub(chordchunk,1,subdiv_numlength)
				--reaper.ShowConsoleMsg("USER ERROR DON'T PUT ANYTHING BUT NUMBERS " .. 'BY "("\n')
			else
				--reaper.ShowConsoleMsg("THERE WAS NO MULTI\n")
				divmult = 1
			end	
			--reaper.ShowConsoleMsg("divmult = " .. divmult .. "\n")
			divtotal = divtotal + divmult
		end		
		--reaper.ShowConsoleMsg("divtotal = " .. divtotal .. "\n")
			for i2, chordchunk in pairs(tablerecords[4]) do			--  PROCESS EACH CHORD CHUNK	
			start_pos_OM_par, _  = string.find(chordchunk, "%(")  -- LOOK IN THAT CHUNK FOR (
			if start_pos_OM_par ~= nil and type(tonumber(string.sub(chordchunk,1,start_pos_OM_par - 1))) == "number" then
				divmult =  tonumber(string.sub(chordchunk,1,start_pos_OM_par - 1))     --  FOUND ANOTHER DIGIT
				nextlayer_table_elem_count = nextlayer_table_elem_count + 1
				new_multi = (processmore_OM_table[i1][2]*divmult)/divtotal
				revised_chunk = string.sub(chordchunk,start_pos_OM_par + 1,string.len(chordchunk)-1)
				start_pos_OM_inwardpar, _  = string.find(revised_chunk, "%(")
				start_pos_OM_inwardsep, _  = string.find(revised_chunk, ";")
				if start_pos_OM_inwardpar == nil and start_pos_OM_inwardsep == nil then
				nextlayer_table[nextlayer_table_elem_count] = {false,new_multi,nextlayer_table_elem_count,{revised_chunk}}				
				else
					OMfalsesofar = OMfalsesofar + 1
					revisedandcleaned = ""
					local par_count_depth = 0
					for iggie = 1,string.len(revised_chunk), 1 do
						if par_count_depth < 0 then
							--user error SEND MESSAGE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						elseif string.sub(revised_chunk,iggie,iggie) == "(" then 
							newcharreplace = "("
							par_count_depth = par_count_depth + 1
						elseif string.sub(revised_chunk,iggie,iggie) == ")" then 
							newcharreplace = ")"
							par_count_depth = par_count_depth - 1							
						elseif string.sub(revised_chunk,iggie,iggie) == ";" and par_count_depth == 0 then 
							newcharreplace = ","
						else
							newcharreplace = string.sub(revised_chunk,iggie,iggie)
						end
						revisedandcleaned = revisedandcleaned .. newcharreplace
					end
					table_of_div_chunks =  Split(revisedandcleaned, ",")
					nextlayer_table[nextlayer_table_elem_count] = {true,new_multi,nextlayer_table_elem_count,{}}
					for idc, vdc in pairs(table_of_div_chunks) do
						nextlayer_table[nextlayer_table_elem_count][4][idc] = vdc
					end
				end	
			elseif start_pos_OM_par ~= nil then              -- FOUND DIVISION MULTI THAT ISN'T A NUMBER
				nextlayer_table_elem_count = nextlayer_table_elem_count + 1
				new_multi = processmore_OM_table[i1][2]/divtotal
				revised_chunk = string.sub(chordchunk,start_pos_OM_par + 1,string.len(chordchunk)-1)				
				start_pos_OM_inwardpar, _  = string.find(revised_chunk, "%(")
				start_pos_OM_inwardsep, _  = string.find(revised_chunk, ";")				
				if start_pos_OM_inwardpar == nil and start_pos_OM_inwardsep == nil then				
					nextlayer_table[nextlayer_table_elem_count] = {false,new_multi,nextlayer_table_elem_count,{revised_chunk}}
				else
					OMfalsesofar = OMfalsesofar + 1
					revisedandcleaned = ""
					local par_count_depth = 0
					for iggie = 1,string.len(revised_chunk), 1 do
						if par_count_depth < 0 then
							--user error SEND MESSAGE !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!
						elseif string.sub(revised_chunk,iggie,iggie) == "(" then 
							newcharreplace = "("
							par_count_depth = par_count_depth + 1
						elseif string.sub(revised_chunk,iggie,iggie) == ")" then 
							newcharreplace = ")"
							par_count_depth = par_count_depth - 1							
						elseif string.sub(revised_chunk,iggie,iggie) == ";" and par_count_depth == 0 then 
							newcharreplace = ","
						else
							newcharreplace = string.sub(revised_chunk,iggie,iggie)
						end
						revisedandcleaned = revisedandcleaned .. newcharreplace
					end
					table_of_div_chunks =  Split(revisedandcleaned, ",")
					nextlayer_table[nextlayer_table_elem_count] = {true,new_multi,nextlayer_table_elem_count,{}}
					for idc, vdc in pairs(table_of_div_chunks) do
						nextlayer_table[nextlayer_table_elem_count][4][idc] = vdc
					end
					-- ALERT USER THAT INPUT IS MESSED UP
				end
			else
				nextlayer_table_elem_count = nextlayer_table_elem_count + 1
				new_multi = processmore_OM_table[i1][2]/divtotal
				nextlayer_table[nextlayer_table_elem_count] = {false,new_multi,nextlayer_table_elem_count,{processmore_OM_table[i1][4][i2]}}
			end	
		end		
		
		
		
		
	end		
--reaper.ShowConsoleMsg(nextlayer_table_elem_count .. ' - ' .. tostring(nextlayer_table[nextlayer_table_elem_count][4]) .. "\n")	
end

if OMfalsesofar > 0 then
cyclecount = cyclecount + 1

	--reaper.ShowConsoleMsg("-------CYCLE COUNT = ------" .. cyclecount ..  "-------PM------\n")
	--table_printed_strings = Table_Print(processmore_OM_table)	
	--reaper.ShowConsoleMsg(table_printed_strings)
	--reaper.ShowConsoleMsg("---------------------------NL----------\n")	
	--table_printed_strings = Table_Print(nextlayer_table)
	--reaper.ShowConsoleMsg(table_printed_strings)	

processmore_OM_table = {}
processmore_OM_table = nextlayer_table
nextlayer_table =  {}

goto run_an_unfolding_cycle





else


	borrow_time = 0
	
	

	for ice = nextlayer_table_elem_count, 1, -1 do
		if (nextlayer_table[ice][2] * 4) - borrow_time > 0 then
			nextlayer_table[ice][2] = (nextlayer_table[ice][2] * 4) - borrow_time
		else
			-- message to user about problem
		end
		if string.sub(nextlayer_table[ice][4][1],1,1) == "~" and nextlayer_table_elem_count > 1 then
			borrow_time = .5
			nextlayer_table[ice][2] = nextlayer_table[ice][2] + borrow_time
			nextlayer_table[ice][4][1] = string.sub(nextlayer_table[ice][4][1],2,string.len(nextlayer_table[ice][4][1]))
		elseif string.sub(nextlayer_table[ice][4][1],1,1) == "<"  and nextlayer_table_elem_count > 1 then
			borrow_time = .25
			nextlayer_table[ice][2] = nextlayer_table[ice][2] + borrow_time
			nextlayer_table[ice][4][1] = string.sub(nextlayer_table[ice][4][1],2,string.len(nextlayer_table[ice][4][1]))
		elseif string.sub(nextlayer_table[ice][4][1],1,1) == "~" and nextlayer_table_elem_count == 1 then
			-- message to user about problem
		elseif string.sub(nextlayer_table[ice][4][1],1,1) == "<"  and nextlayer_table_elem_count == 1 then
			-- message to user about problem		
		else
			borrow_time = 0		
		end
	end

	
cyclecount = cyclecount + 1
	--reaper.ShowConsoleMsg("-----LAST CYCLE COUNT = ---" .. cyclecount ..  "------PM-------\n")
	--table_printed_strings = Table_Print(processmore_OM_table)	
	--reaper.ShowConsoleMsg(table_printed_strings)
	--reaper.ShowConsoleMsg("-----------------------------NL--------\n")	
	--table_printed_strings = Table_Print(nextlayer_table)
	--reaper.ShowConsoleMsg(table_printed_strings)		


	theresultofprocessOMbars = ""
	OM_swaplist2 = {
{"%$r%$","rest"},
{"{"," <"},
{"}","> "},
{"> ",">"},
{" <","<"}
}

		if musictheory.key_table[ckeyfound] ~= nil then
		keyshifter_OM = musictheory.key_table[ckeyfound]
		isitflat = musictheory.is_it_flat_table[ckeyfound]
		--reaper.ShowConsoleMsg("Keyshift = " .. keyshifter_OM .. " Is flat is " .. tostring(isitflat) .. "\n")
		
		else 
		-- message and cancel
		--reaper.ShowConsoleMsg("was nil\n")
		end
	for iome = 1, nextlayer_table_elem_count, 1 do
		the_itemOM = nextlayer_table[iome][4][1]
		the_itemOM = Swapout(the_itemOM, OM_swaplist2)
		if string.sub(the_itemOM,1,1) == "b" or string.sub(the_itemOM,1,1) == "#" then
		da_root = string.sub(the_itemOM,1,2)
		da_rest =  string.sub(the_itemOM,3,string.len(the_itemOM))
		else
		da_root = string.sub(the_itemOM,1,1)
		da_rest =  string.sub(the_itemOM,2,string.len(the_itemOM))
		end
		
		if musictheory.root_table[da_root] ~= nil then
			combo_shift = musictheory.root_table[da_root] + keyshifter_OM
			if combo_shift > 23 then
				combo_shift = combo_shift - 24
			elseif combo_shift > 11 then
				combo_shift = combo_shift - 12
			elseif combo_shift < 0 then
				combo_shift = combo_shift + 12
			else
			end
			if isitflat then
				letter_r_root = musictheory.flats_table[combo_shift]
			else
				letter_r_root = musictheory.sharps_table[combo_shift]
			end
			
			
			
			
cob_start, cob_end  = string.find(da_rest, "/")		
if cob_start ~= nil then
da_bass = string.sub(da_rest, cob_start + 1, string.len(da_rest))


		if string.sub(da_bass,1,1) == "b" then
		da_real_bass = string.sub(da_bass,1,2)
		da_pre_bass =  string.sub(da_rest,1,cob_start)
			--reaper.ShowConsoleMsg("flat = " .. da_real_bass .. "\n")
		elseif string.sub(da_bass,1,1) == "#" then
		da_real_bass = string.sub(da_bass,1,2)
		da_pre_bass =  string.sub(da_rest,1,cob_start)		
		--reaper.ShowConsoleMsg("sharp = " .. da_real_bass .. "\n")
		else
		da_real_bass = string.sub(da_bass,1,1)
		da_pre_bass =  string.sub(da_rest,1,cob_start)
		end
		
		if musictheory.root_table[da_real_bass] ~= nil then
			combo_shift = musictheory.root_table[da_real_bass] + keyshifter_OM
			if combo_shift > 23 then
				combo_shift = combo_shift - 24
			elseif combo_shift > 11 then
				combo_shift = combo_shift - 12
			elseif combo_shift < 0 then
				combo_shift = combo_shift + 12
			else
			end
			if isitflat then
				letter_bass = musictheory.flats_table[combo_shift]
			else
				letter_bass = musictheory.sharps_table[combo_shift]
			end
		
	
			the_itemOM = letter_r_root .. da_pre_bass .. letter_bass

		end





else
			the_itemOM = letter_r_root .. da_rest
end

			
			
			
			
			

			
		else
		-- warn missing root
		end
		
		if nextlayer_table[iome][2] > 0 then
		fraction = Provide_Fraction(nextlayer_table[iome][2],1)
			added_element = " " .. tostring(fraction).. the_itemOM
		else
			added_element = " " .. the_itemOM
		end
	
	

	
	
	--reaper.ShowConsoleMsg(added_element .. "\n")
	theresultofprocessOMbars = theresultofprocessOMbars .. added_element
	end

	end	
	theresultofprocessOMbars =  cbpmfound .. "BPM " .. 	theresultofprocessOMbars 
	
return theresultofprocessOMbars

end











function export_ccc()
ccc_ex_warning = ""
ccc_export_area = ""
reaper.PreventUIRefresh(1)
the_last_ccc_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
_, ctitle_startso  = string.find(header_area, "Title: ")			-- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
ctitle_endso, _  = string.find(header_area, "Writer:")
_, cwriter_startso  = string.find(header_area, "Writer: ")
cwriter_endso, _  = string.find(header_area, "BPM:")
_, ckey_startso  = string.find(header_area, "Key: ")
ckey_endso, _  = string.find(header_area, "Swing:")
_, cbpm_startso  = string.find(header_area, "BPM: ")
cbpm_endso, _  = string.find(header_area, "Key:")
ctitlefound = string.sub(header_area, ctitle_startso+1, ctitle_endso-2)
cwriterfound = string.sub(header_area, cwriter_startso+1, cwriter_endso-2)
cbpmfound = string.sub(header_area, cbpm_startso+1, cbpm_endso-2)
ckeyfound = string.sub(header_area, ckey_startso+1, ckey_endso-2)



-- https://www.chordsheet.com/song/populate-new?title=Your%20Title&artist=Your%20Artist&chords=A%20B%20C%20D%20%0AA%20B%20C%20D&key=Bbm&bpm=96



ctitlefound = urlencode(ctitlefound)
cwriterfound = urlencode(cwriterfound)
unencoded_keyfound = ckeyfound
ckeyfound = urlencode(ckeyfound)
cbpmfound = urlencode(cbpmfound)

cccchords = process_ccc_bars()
cccchords = urlencode(cccchords)


if cccchords ~= "Error..." then

ulink = '"https://www.chordsheet.com/song/populate-new?title=' .. ctitlefound .. '&artist=' .. cwriterfound .. '&chords=' .. cccchords .. '&key=' .. ckeyfound .. '&bpm=' .. cbpmfound .. '&nns=1"'

ccclink = ulink

--Your%20Title&artist=Your%20Artist&chords=A%20B%20C%20D%20%0AA%20B%20C%20D&key=Bbm&bpm=96"'




--reaper.ShowConsoleMsg(ccclink..'\n\n')
ccc_renderd = true 
end

end



























































































































char_to_hex = function(c)
  return string.format("%%%02X", string.byte(c))
end

function urlencode(theurl)
  if theurl == nil then
    return
  end
  theurl = theurl:gsub("\n", "\r\n")
  theurl = theurl:gsub("([^%w _%%%-%.~])", char_to_hex)
  theurl = theurl:gsub(" ", "+")
  return theurl
  
  
-- https://gist.github.com/liukun/f9ce7d6d14fa45fe9b924a3eed5c3d99
-- ref: https://gist.github.com/ignisdesign/4323051
-- ref: http://stackoverflow.com/questions/20282054/how-to-urldecode-a-request-uri-string-in-lua
-- to encode table as parameters, see https://github.com/stuartpb/tvtropes-lua/blob/master/urlencode.lua
  
  
end






















































































































































































































































































































































































































































































ccc_ex_warning = ""
---------------------------------------------------------Chordsheet Com Create SUB FOR PROCESSESSING ALL THE BARS
function process_ccc_bars()
thefail = ""
    chord_charting_area = inital_swaps(chord_charting_area)
    unfolded_ccc_data, error_zone = form.process_the_form(header_area, chord_charting_area) 
														-- FORM		 DEAL WITH UNFOLDING THE FORM
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "{", "=")
	
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "$}", "|")
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%$", "")
--unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%%", "!Repeat!")
													   -- CODE THE SIMPLEST AS A OR B SECTIONS DELETE THE REST
												
--reaper.ShowConsoleMsg(unfolded_ccc_data.. "\n")

												
::striplabels::																-- REMOVE THE SECTION LABELS
local in_num = string.len(unfolded_ccc_data)
section_start, _  = string.find(unfolded_ccc_data, "=")
_, section_end  = string.find(unfolded_ccc_data, "|")
if section_start ~= nil and section_end ~= nil and section_end > section_start then
--reaper.ShowConsoleMsg("did find\n")
--unfolded_ccc_data = string.gsub(unfolded_ccc_data, string.sub(unfolded_ccc_data,section_start,section_end) , "")
--else
--reaper.ShowConsoleMsg("didn't find\n")
end
if in_num ~= string.len(unfolded_ccc_data) then
goto striplabels
end

																-- CONVERT RETURNS TO SPACES
																
		



::flaten::																	-- CONVERT RETURNS TO SPACES
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\n" , " ")
if in_num ~= string.len(unfolded_ccc_data) then
goto flaten
end

::detab::																	-- CONVERT TABS TO SPACES
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\t" , " ")
if in_num ~= string.len(unfolded_ccc_data) then
goto detab
end
																			-- TRIM DOWN TO SINGLE SPACES
::trimwhitespace::
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "  " , " ")
if in_num ~= string.len(unfolded_ccc_data) then
goto trimwhitespace
end

::reducecr::																-- ?? TRIM BACK RETURNS (didn't I do this)
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "\n\n" , "\n")
if in_num ~= string.len(unfolded_ccc_data) then
goto reducecr
end

::fluffen::																	-- SEPARATE BRACED MEASURES BY A SPACE
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%]%[" , "] [")
if in_num ~= string.len(unfolded_ccc_data) then
goto fluffen
end

::squish1::																	-- TRIM OUT SPACES FROM INSIDE IN BRACES
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, "%[ " , "[")
if in_num ~= string.len(unfolded_ccc_data) then
goto squish1
end
																			
::squish2::																	-- TRIM OUT SPACES FROM INSIDE OUT BRACES
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, " %]" , "]")
if in_num ~= string.len(unfolded_ccc_data) then
goto squish2
end

::derestrest::																	-- CONVERT ALL REST TO Chordsheet REST 1.
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, " %- " , " rr ")
unfolded_ccc_data = string.gsub(unfolded_ccc_data, " R " , " rr ")
if in_num ~= string.len(unfolded_ccc_data) then
goto derestrest
end


	::derest::																	-- CONVERT ALL REST TO Chordsheet REST 1.
in_num = string.len(unfolded_ccc_data)
unfolded_ccc_data = string.gsub(unfolded_ccc_data, " rr " , " r ")
if in_num ~= string.len(unfolded_ccc_data) then
goto derest
end

		






local inmeasurenow = false		-- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
measurechord_count = 0
rebuild = ""
for i = 1,string.len(unfolded_ccc_data) do
	if string.sub(unfolded_ccc_data,i,i) == "=" then
		rebuild = rebuild .. string.sub(unfolded_ccc_data,i,i)			-- REBUILD WITH SECTION SWAP AS IS
		inmeasurenow = false
	elseif string.sub(unfolded_ccc_data,i,i) == "[" and inmeasurenow == false then
		inmeasurenow = true
		rebuild = rebuild .. string.sub(unfolded_ccc_data,i,i)			-- REBUILD WITH IN BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_ccc_data,i,i) == "]" and inmeasurenow == true then
		inmeasurenow = false
		rebuild = rebuild .. string.sub(unfolded_ccc_data,i,i)			-- REBUILD WITH OUT BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_ccc_data,i,i) == "]" and inmeasurenow == false then  -- WARN WHEN THERE IS A [[ USER ERROR
		thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
	elseif string.sub(unfolded_ccc_data,i,i) == "[" and inmeasurenow == true then	 -- WARN WHEN THERE IS A ]] USER ERROR
		thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
	elseif string.sub(unfolded_ccc_data,i,i) == " " and inmeasurenow == false then
		rebuild = rebuild .. ","													-- CHANGE MEASURE SEPARATORS TO COMMA
	elseif string.sub(unfolded_ccc_data,i,i) == " " and inmeasurenow == true then
		rebuild = rebuild .. ":"													-- CHANGE IN MEASURE SEPS TO COLON
	else
		rebuild = rebuild .. string.sub(unfolded_ccc_data,i,i)						-- PASS EVERYTHING ELSE AS IS
	end
end
ccc_main_bars_table = Split(rebuild, ",")											-- PUT THE DATA INTO TABLE






local warned = false																		-- PREPING VARIABLES
local rewarned = false
local newtablevalue = ""
local processmore_table = {}
local ccc_post_table_chord_data = ""


for ib,vb in pairs(ccc_main_bars_table) do		--  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
	if string.find(vb, "%[") then
		processmore_table[ib] = {true,1}											-- TAG AS MULTIBAR IN this TABLE
	elseif string.find(vb, "=") then
		processmore_table[ib] = {false,0}											-- A) SECTION HEADER - NOT A MEASURE
	else
		processmore_table[ib] = {false,1}											-- TAG AS A SINGLE BAR
	end
		--reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
end



for ipm,vpm in pairs(processmore_table) do		-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DEAL WITH ALL THE MULTIBARS     !!!!!!!
barmultiplier = 0
	if processmore_table[ipm][1] then
		if string.sub(ccc_main_bars_table[ipm],1,1) ~= "[" then				-- 	CHECK TO SEE IF MULTIBAR
			if string.find(ccc_main_bars_table[ipm],":") then
				startsbrace,endbrace = string.find(ccc_main_bars_table[ipm],"%[",1)
				--reaper.ShowConsoleMsg(startsbrace.."\n")
				barmultiplier = tonumber(string.sub(ccc_main_bars_table[ipm],1,startsbrace-1))
				if barmultiplier ~= nil and barmultiplier ~= 1 then				-- MULTIBAR WITH MULTI CHORDS = BAD
					if warned == false then
						ccc_ex_warning = ccc_ex_warning .. '- Multibars with more than one chord are not supported in Chordsheet.com export\nbecause they easily result in rhythms Chordsheet.com can not accept as input.\nThese measures have been rendered as "NC" which will help you find \nand adjust them.\n\n'
						warned = true
					end
					newtablevalue = "NC "
					for count = 1,barmultiplier-1,1 do
						newtablevalue = newtablevalue .. "NC "
					end
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = barmultiplier
					
				elseif barmultiplier ~= nil and barmultiplier == 1 then	
					newtablevalue = string.sub(ccc_main_bars_table[ipm],startsbrace, string.len(ccc_main_bars_table[ipm]))

					processmore_table[ipm][1] = true
					processmore_table[ipm][2] = 0				

				else												-- LIKELY USER SCREW UP NON NUMBER MULTIBAR ie G[2m 5]
					ccc_ex_warning = ccc_ex_warning .. '- Looks like your chord entry has formatting error.\nIt has been rendered as "NC" so you can find and manually adjust the error.'
					newtablevalue = "NC "
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1
				end
				
			else																-- ONLY ONE INTERNAL CHORD ALL GOOD
				startsbrace,endbrace = string.find(ccc_main_bars_table[ipm],"%[",1)
				--reaper.ShowConsoleMsg(startsbrace.."\n")
				barmultiplier = tonumber(string.sub(ccc_main_bars_table[ipm],1,startsbrace-1))
				if barmultiplier ~= nil then   ---!!!!!!!!!!!!!!!!!!! THIS WORKS BUT SHOULDN'T !!! WHY ???????????
					newtablevalue_part = string.sub(ccc_main_bars_table[ipm],startsbrace+1, string.len(ccc_main_bars_table[ipm])-1)
					for count = 1,barmultiplier,1 do
						newtablevalue = newtablevalue .. " " .. newtablevalue_part .. " "
					end
					processmore_table[ipm][2] = barmultiplier				
				else								-- LIKELY USER ERROR - ONLY 1 INTERNAL CHORD, BUT BAD MULTI ie G[4]
					ccc_ex_warning = ccc_ex_warning .. '- Looks like your chord entry has formatting error.\nIt has been rendered as ' .. string.sub(ccc_main_bars_table[ipm],startsbrace+1,string.len(ccc_main_bars_table[ipm])-1) .. ' so you can find and manually adjust the error.\n'
					newtablevalue = string.sub(ccc_main_bars_table[ipm],startsbrace+1,string.len(ccc_main_bars_table[ipm])-1)
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1
				end
			end
			ccc_main_bars_table[ipm] = newtablevalue
		end
	--reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
	end
end
ccc_measurecount_total = 0						-- LABEL ALL THE MEASURES ACCORDING TO THEIR MEASURE NUMBER 
for i,v in pairs(processmore_table) do
	ccc_measurecount_total = ccc_measurecount_total + processmore_table[i][2]
	processmore_table[i][3] = ccc_measurecount_total
end




in_item_table = {}					--  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! DEAL WITH BRACED MEASURE INTERNALS
for i,v in pairs(processmore_table) do
	if processmore_table[i][1] then
		inmeasure_table = Split(string.sub(ccc_main_bars_table[i],2,string.len(ccc_main_bars_table[i])-1), ":")
		--reaper.ShowConsoleMsg(string.sub(ccc_main_bars_table[i],2,string.len(ccc_main_bars_table[i])-1) .. "\n")
		buileroo = ""
		split_mult_total = 0
		chord_count_total = 0
			in_item_table = {}		
		for ibt,vbt in pairs(inmeasure_table) do
			chord_count_total = chord_count_total + 1		

		
			item_split_starter,item_split_ender = string.find(vbt, "%(",1)	
			if item_split_starter ~= nil then
				--reaper.ShowConsoleMsg("found it\n")
				split_mult = tonumber(string.sub(vbt,1,item_split_starter-1))
				split_mult_total = split_mult_total + split_mult
				in_item_table[ibt] = {split_mult, string.sub(vbt,item_split_starter + 1,string.len(vbt) - 1)}
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")				
			else
				--reaper.ShowConsoleMsg("nope\n")	
				split_mult = 1				
				split_mult_total = split_mult_total + split_mult
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. ' string = ' .. string.sub(vbt,1,string.len(vbt)) .. "\n")
				in_item_table[ibt] = {1,vbt}
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")		
			end
		end
----------------------------------------------------------------------------------------
		
		for ig,vg in pairs(in_item_table) do
			addstart = 1
			if string.sub(vg[2],1,1) == " " then
				addstart = 2
			else
			end
			if string.sub(vg[2],addstart,addstart) == "^" then
				if string.sub(vg[2],addstart + 1 ,addstart + 1) == "^" then
					addstart = addstart + 2
				else
					addstart = addstart + 1
				end
			else
			end
			if string.sub(vg[2],addstart,addstart) == "b" or string.sub(vg[2],addstart,addstart) == "#" then
				addstart = addstart + 2
			else
				addstart = addstart + 1
			end
			endtype,_ = string.find(vg[2], "/")
			if endtype ~= nil then endtype = endtype - 1 end
			if endtype == nil then endtype,_ = string.find(string.sub(vg[2],2,string.len(vg[2]))," ") end
			if endtype == nil then endtype = string.len(vg[2]) end
				replacetype = string.sub(vg[2],addstart, endtype)
				--reaper.ShowConsoleMsg(replacetype .. "\n")
			if musictheory.to_ccc_translation[replacetype] ~= nil then
				in_item_table[ig][2] = string.sub(vg[2],1,addstart-1) .. musictheory.to_ccc_translation[replacetype] .. string.sub(vg[2],endtype + 1, string.len(vg[2]))
			end
		end
		
		
		
		
		
----------------------------------------------------------------------------------------		
		if chord_count_total == 1 then
			buileroo = in_item_table[1][2] .. " "
		elseif chord_count_total == 2 and in_item_table[1][1] == in_item_table[2][1] then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 3 and tonumber(in_item_table[2][1]) == 1 then
			buileroo = in_item_table[1][2] .. "_/_/_" .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 3 then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_/_/ "
		elseif chord_count_total == 2 and in_item_table[1][1] > in_item_table[2][1] then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. ccc_main_bars_table[i] .. ' may have been simplified.\n'
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and in_item_table[1][1] < in_item_table[2][1] then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. ccc_main_bars_table[i] .. ' may have been simplified.\n'
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. " "			
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 2 and tonumber(in_item_table[2][1]) == 1 and tonumber(in_item_table[3][1]) == 1 then
			buileroo = in_item_table[1][2] .. "_/_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 1 and tonumber(in_item_table[3][1]) == 2 then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_/ "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 2 and tonumber(in_item_table[3][1]) == 1 then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_/_" .. in_item_table[3][2] .. " "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) > tonumber(in_item_table[2][1]) and tonumber(in_item_table[1][1]) > tonumber(in_item_table[3][1]) then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. ccc_main_bars_table[i] .. ' may have been simplified.\n'			
		elseif chord_count_total == 3 and tonumber(in_item_table[3][1]) > tonumber(in_item_table[1][1]) and tonumber(in_item_table[3][1]) > tonumber(in_item_table[2][1]) then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. ccc_main_bars_table[i] .. ' may have been simplified.\n'			
		elseif chord_count_total == 3 and tonumber(in_item_table[2][1]) > tonumber(in_item_table[1][1]) and tonumber(in_item_table[2][1]) > tonumber(in_item_table[3][1]) then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. ccc_main_bars_table[i] .. ' may have been simplified.\n'		
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. " "
			
		elseif chord_count_total == 4 and tonumber(in_item_table[1][1]) == tonumber(in_item_table[2][1]) and  tonumber(in_item_table[1][1]) == tonumber(in_item_table[3][1]) and tonumber(in_item_table[1][1]) == tonumber(in_item_table[4][1]) then
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_" .. in_item_table[4][2] .. " "

		elseif chord_count_total == 4 and split_mult_total > 4 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure '  .. processmore_table[i][3] .. ' ' .. '\nthe rhythm of chords ' .. ccc_main_bars_table[i] .. '\n was simplified due to Chord Sheet limititations.\n'
			buileroo = in_item_table[1][2] .. "_" .. in_item_table[2][2] .. "_" .. in_item_table[3][2] .. "_" .. in_item_table[4][2] .. " "
			
			
		elseif chord_count_total == 5 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' rhythm could not be rendered due to Chord Sheet limitations.\n'
			buileroo = in_item_table[1][2] .. '_' .. in_item_table[2][2] .. '_' .. in_item_table[3][2] .. '_' .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. " "				
			
		elseif chord_count_total == 6 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' rhythm could not be rendered due to Chord Sheet limitations.\n'
			buileroo = in_item_table[1][2] .. '_' .. in_item_table[2][2] .. '_' .. in_item_table[3][2] .. '_' .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. '_' .. in_item_table[6][2] .. " "				
			
		elseif chord_count_total == 7 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' rhythm could not be rendered due to Chord Sheet limitations.\n'
			buileroo = in_item_table[1][2] .. '_' .. in_item_table[2][2] .. '_' .. in_item_table[3][2] .. '_' .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. '_' .. in_item_table[6][2] .. '_' .. in_item_table[7][2] .. " "			
			
			
		elseif chord_count_total == 8 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' rhythm could not be rendered due to Chord Sheet limitations.\n'
			buileroo = in_item_table[1][2] .. '_' .. in_item_table[2][2] .. '_' .. in_item_table[3][2] .. '_' .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. '_' .. in_item_table[6][2] .. '_' .. in_item_table[7][2] .. '_' .. in_item_table[8][2] .. " "
			
		
			
			
		elseif chord_count_total > 8 then
			ccc_ex_warning = ccc_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' ' .. ccc_main_bars_table[i] .. '\nonly the chords ' .. in_item_table[1][2] .. ' ' .. in_item_table[2][2] .. ' ' .. in_item_table[3][2] .. ' ' .. in_item_table[4][2] .. " " .. in_item_table[5][2] .. ' ' .. in_item_table[6][2] .. ' ' .. in_item_table[7][2] .. ' ' .. in_item_table[8][2] .. '\n could be rendered due to Chord Sheet limit of 8 chords per bar.\n'
			buileroo = in_item_table[1][2] .. '_' .. in_item_table[2][2] .. '_' .. in_item_table[3][2] .. '_' .. in_item_table[4][2] .. "_" .. in_item_table[5][2] .. '_' .. in_item_table[6][2] .. '_' .. in_item_table[7][2] .. '_' .. in_item_table[8][2] .. " "
			
		else
			buileroo = ccc_main_bars_table[i]
		end
		
		ccc_main_bars_table[i] = buileroo

	else
		this_single_chord = ccc_main_bars_table[i]
		addstart = 1
		if string.sub(this_single_chord,1,1) == " " then
			addstart = 2
		else
		end
		if string.sub(this_single_chord,addstart,addstart) == "<" then
			if string.sub(this_single_chord,addstart + 1 ,addstart + 1) == "<" then
				addstart = addstart + 2
			else
				addstart = addstart + 1
			end
		else
		end
		if string.sub(this_single_chord,addstart,addstart) == "b" or string.sub(this_single_chord,addstart,addstart) == "#" then
			addstart = addstart + 2
		else
			addstart = addstart + 1
		end
		endtype,_ = string.find(this_single_chord, "/")
		if endtype ~= nil then endtype = endtype - 1 end
		if endtype == nil then endtype,_ = string.find(string.sub(this_single_chord,2,string.len(this_single_chord))," ") end
		if endtype == nil then endtype = string.len(this_single_chord) end
		replacetype = string.sub(this_single_chord,addstart, endtype)
		--reaper.ShowConsoleMsg(replacetype .. "\n")
		if musictheory.to_ccc_translation[replacetype] ~= nil then
			ccc_main_bars_table[i] = string.sub(this_single_chord,1,addstart-1) .. musictheory.to_ccc_translation[replacetype] .. string.sub(this_single_chord,endtype + 1, string.len(this_single_chord))
		end
	end

end

for i,v in pairs(ccc_main_bars_table) do							--	DEAL WITH REPEATS ON THE WAY TO TEXT
	if v == "!Repeat!" then
	ccc_post_table_chord_data = ccc_post_table_chord_data .. "  "  .. the_last_ccc_bar_content
	else
	ccc_post_table_chord_data = ccc_post_table_chord_data .. "  "  .. v
	the_last_ccc_bar_content = v
	end
end
																					
--ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "| Â |", "|A) ")		-- SWAP OUT FOR A)
--ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "| Å |", "|B) ")			-- AND B) SECTION MARKS
--ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "<<", "")			-- SWAP OUT FOR 16th 
--ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "<", "")					-- AND 8th PUSHES IN ccc FORMAT

--reaper.ShowConsoleMsg("cf = "..unencoded_keyfound.. "\n")
ccc_key_shift = musictheory.key_table[unencoded_keyfound]



if ccc_key_shift ~= nil then 


--reaper.ShowConsoleMsg("cccks = "..ccc_key_shift.. "\n")



ccc_flat = musictheory.is_it_flat_table[ckeyfound]
--reaper.ShowConsoleMsg("cccf = "..tostring(ccc_flat).. "\n")

else
--reaper.ShowConsoleMsg("Check your key.\nNumbers2Notes, like many Nashville Number System users, does not use minor keys.\n Instead, use the relative major and write your charts with the focus on 6m rather than 1.\n")


return "Error...",0,"Check your key.\nNumbers2Notes, like many Nashville Number System users, does not use minor keys.\n Instead, use the relative major and write your charts with the focus on 6m rather than 1.\n"
end


	for i,v in pairs(musictheory.cccroot_table) do
		if v + ccc_key_shift >= 12 then
			totalshift = v + ccc_key_shift - 12
		elseif v + ccc_key_shift < 0 then
			totalshift = v + ccc_key_shift + 12			
		else
			totalshift = v + ccc_key_shift
		end
		--reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
		if ccc_flat then
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, " ".. i, musictheory.flats_table[totalshift])
		else
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, " ".. i, musictheory.sharps_table[totalshift])
		end
	end

	for i,v in pairs(musictheory.cccroot_table) do
		if v + ccc_key_shift >= 12 then
			totalshift = v + ccc_key_shift - 12
		elseif v + ccc_key_shift < 0 then
			totalshift = v + ccc_key_shift + 12					
		else
			totalshift = v + ccc_key_shift	
		end
		--reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
		if ccc_flat then
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "/".. i, "/".. musictheory.flats_table[totalshift])
		else
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "/".. i, "/".. musictheory.sharps_table[totalshift])
		end
	end


	for i,v in pairs(musictheory.cccroot_table) do
		if v + ccc_key_shift >= 12 then
			totalshift = v + ccc_key_shift - 12
		elseif v + ccc_key_shift < 0 then
			totalshift = v + ccc_key_shift + 12				
		else
			totalshift = v + ccc_key_shift
		end
		--reaper.ShowConsoleMsg("ccctf = "..tostring(totalshift).. "\n")
		if ccc_flat then
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "_".. i, "_".. musictheory.flats_table[totalshift])
		else
				ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "_".. i, "_".. musictheory.sharps_table[totalshift])
		end
	end



::doubleclean::																	-- CONVERT RETURNS TO SPACES
in_num = string.len(ccc_post_table_chord_data)
ccc_post_table_chord_data = string.gsub(ccc_post_table_chord_data, "  " , " ")
if in_num ~= string.len(ccc_post_table_chord_data) then
goto doubleclean
end

last_ccc_rebuild_for_4bar_lines = ""
spacecounter = 1
for i = 1,string.len(ccc_post_table_chord_data),1 do
	if string.sub(ccc_post_table_chord_data,i,i) == " " then
		if spacecounter == 4 then 
		spacecounter = 1
		last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. "\n"
		else
		spacecounter = spacecounter + 1
		last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. string.sub(ccc_post_table_chord_data,i,i)
		end
	elseif string.sub(ccc_post_table_chord_data,i,i) == "|" then
		last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. "\n"
		spacecounter = 0		
	else
		last_ccc_rebuild_for_4bar_lines = last_ccc_rebuild_for_4bar_lines .. string.sub(ccc_post_table_chord_data,i,i)
	end


end
ccc_post_table_chord_data = last_ccc_rebuild_for_4bar_lines


the_ccc_bar_count = 0
--reaper.ShowConsoleMsg("\n-----------------------------------------\n")
for i,v in pairs(processmore_table) do
	the_ccc_bar_count = the_ccc_bar_count + tonumber(processmore_table[i][2])
	--reaper.ShowConsoleMsg("COUNT = " .. tonumber(processmore_table[i][2]) .. "TOTAL = " .. the_ccc_bar_count .. "\n")
end
return ccc_post_table_chord_data, the_ccc_bar_count, thefail
end



















































































































































































































































































































































































































































































































































































































the_last_BIAB_bar_content = ""
function export_biab()
biab_ex_warning = ""
biab_export_area = ""
reaper.PreventUIRefresh(1)
the_last_BIAB_bar_content = "" -- CLEAR OUT THE OLD AND SET UP THE SHELL FOR THE NEW DATA
local headshell = [[
"[Song]
[Title !W! - !T!]
[Key !K!] 
[Tempo !B!]
[Form 1-!F!*1]
[.sty _!S!.sty]
[Chords]
[Fix]
!C!
[ChordsEnd]
[SongEnd]"]]
to_biab_export_area = headshell									
_, title_startso  = string.find(header_area, "Title: ")			-- GET THE PROJECT SETTINGS AND PLACE IN THE SHELL
title_endso, _  = string.find(header_area, "Writer:")
_, writer_startso  = string.find(header_area, "Writer: ")
writer_endso, _  = string.find(header_area, "BPM:")
_, key_startso  = string.find(header_area, "Key: ")
key_endso, _  = string.find(header_area, "Swing:")
_, bpm_startso  = string.find(header_area, "BPM: ")
bpm_endso, _  = string.find(header_area, "Key:")
titlefound = string.sub(header_area, title_startso+1, title_endso-2)
writerfound = string.sub(header_area, writer_startso+1, writer_endso-2)
bpmfound = string.sub(header_area, bpm_startso+1, bpm_endso-2)
keyfound = string.sub(header_area, key_startso+1, key_endso-2)
to_biab_export_area = string.gsub(to_biab_export_area, "!W!", writerfound)
to_biab_export_area = string.gsub(to_biab_export_area, "!T!", titlefound)
to_biab_export_area = string.gsub(to_biab_export_area, "!K!", keyfound)
to_biab_export_area = string.gsub(to_biab_export_area, "!B!", bpmfound)
to_biab_export_area = string.gsub(to_biab_export_area, "!S!", biab_style)
biab_bars, biab_bar_count = process_biab_bars()								-- MOST WORK IS HERE IN THIS SUB
to_biab_export_area = string.gsub(to_biab_export_area, "!F!", biab_bar_count)
to_biab_export_area = string.gsub(to_biab_export_area, "!C!", biab_bars)
if string.len(biab_ex_warning) > 0 then
biab_export_area = biab_ex_warning .. "_____________________________________\n\n" .. to_biab_export_area
else
biab_export_area = to_biab_export_area
end
reaper.PreventUIRefresh(-1)
end



biab_ex_warning = ""
---------------------------------------------------------BIAB SUB FOR PROCESSESSING ALL THE BARS
function process_biab_bars()
thefail = ""
    chord_charting_area = inital_swaps(chord_charting_area)
    unfolded_biab_data, error_zone = form.process_the_form(header_area, chord_charting_area) 
														-- FORM		 DEAL WITH UNFOLDING THE FORM
unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Intro$}", "Â")	
unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Verse$}", "Â")
unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Chorus$}", "Å")
unfolded_biab_data = string.gsub(unfolded_biab_data, "{$Outro$}", "Å")
unfolded_biab_data = string.gsub(unfolded_biab_data, "%%", "!Repeat!")
													   -- CODE THE SIMPLEST AS A OR B SECTIONS DELETE THE REST
													   
::striplabels::																-- REMOVE THE SECTION LABELS
local in_num = string.len(unfolded_biab_data)
section_start, _  = string.find(unfolded_biab_data, "{%$")
_, section_end  = string.find(unfolded_biab_data, "%$}")
if section_start ~= nil and section_end ~= nil and section_end > section_start then
--reaper.ShowConsoleMsg("did find\n")
unfolded_biab_data = string.gsub(unfolded_biab_data, string.sub(unfolded_biab_data,section_start,section_end) , "")
--else
--reaper.ShowConsoleMsg("didn't find\n")
end
if in_num ~= string.len(unfolded_biab_data) then
goto striplabels
end

																-- CONVERT RETURNS TO SPACES
																
		



::flaten::																	-- CONVERT RETURNS TO SPACES
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "\n" , " ")
if in_num ~= string.len(unfolded_biab_data) then
goto flaten
end

::detab::																	-- CONVERT TABS TO SPACES
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "\t" , " ")
if in_num ~= string.len(unfolded_biab_data) then
goto detab
end
																			-- TRIM DOWN TO SINGLE SPACES
::trimwhitespace::
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "  " , " ")
if in_num ~= string.len(unfolded_biab_data) then
goto trimwhitespace
end

::reducecr::																-- ?? TRIM BACK RETURNS (didn't I do this)
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "\n\n" , "\n")
if in_num ~= string.len(unfolded_biab_data) then
goto reducecr
end

::fluffen::																	-- SEPARATE BRACED MEASURES BY A SPACE
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "%]%[" , "] [")
if in_num ~= string.len(unfolded_biab_data) then
goto fluffen
end

::squish1::																	-- TRIM OUT SPACES FROM INSIDE IN BRACES
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, "%[ " , "[")
if in_num ~= string.len(unfolded_biab_data) then
goto squish1
end
																			
::squish2::																	-- TRIM OUT SPACES FROM INSIDE OUT BRACES
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, " %]" , "]")
if in_num ~= string.len(unfolded_biab_data) then
goto squish2
end

::derest::																	-- CONVERT ALL REST TO BIAB REST 1.
in_num = string.len(unfolded_biab_data)
unfolded_biab_data = string.gsub(unfolded_biab_data, " %- " , " 1. ")
unfolded_biab_data = string.gsub(unfolded_biab_data, " R " , " 1. ")
unfolded_biab_data = string.gsub(unfolded_biab_data, " r " , " 1. ")
if in_num ~= string.len(unfolded_biab_data) then
goto derest
end


			






local inmeasurenow = false		-- !!!!!!!!!!!!!!!!   GET THE DATA READY TO BE PUT INTO TABLES ONE CHAR AT A TIME  !!!!!!
measurechord_count = 0
rebuild = ""
for i = 1,string.len(unfolded_biab_data) do
	if string.sub(unfolded_biab_data,i,i) == "Â" or string.sub(unfolded_biab_data,i,i) == "Å" then
		rebuild = rebuild .. string.sub(unfolded_biab_data,i,i)			-- REBUILD WITH SECTION SWAP AS IS
		inmeasurenow = false
	elseif string.sub(unfolded_biab_data,i,i) == "[" and inmeasurenow == false then
		inmeasurenow = true
		rebuild = rebuild .. string.sub(unfolded_biab_data,i,i)			-- REBUILD WITH IN BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_biab_data,i,i) == "]" and inmeasurenow == true then
		inmeasurenow = false
		rebuild = rebuild .. string.sub(unfolded_biab_data,i,i)			-- REBUILD WITH OUT BRACE AS IS (UNLESS...)
	elseif string.sub(unfolded_biab_data,i,i) == "]" and inmeasurenow == false then  -- WARN WHEN THERE IS A [[ USER ERROR
		thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
	elseif string.sub(unfolded_biab_data,i,i) == "[" and inmeasurenow == true then	 -- WARN WHEN THERE IS A ]] USER ERROR
		thefail = thefail .. 'Incident of mismatched braces.  Make sure to use "[" and "]" in pairs.\n'
	elseif string.sub(unfolded_biab_data,i,i) == " " and inmeasurenow == false then
		rebuild = rebuild .. ","													-- CHANGE MEASURE SEPARATORS TO COMMA
	elseif string.sub(unfolded_biab_data,i,i) == " " and inmeasurenow == true then
		rebuild = rebuild .. ":"													-- CHANGE IN MEASURE SEPS TO COLON
	else
		rebuild = rebuild .. string.sub(unfolded_biab_data,i,i)						-- PASS EVERYTHING ELSE AS IS
	end
end
BIAB_main_bars_table = Split(rebuild, ",")											-- PUT THE DATA INTO TABLE






local warned = false																		-- PREPING VARIABLES
local rewarned = false
local newtablevalue = ""
local processmore_table = {}
local BIAB_post_table_chord_data = ""


for ib,vb in pairs(BIAB_main_bars_table) do		--  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DETERMINE IF MULTIBAR !!!!!!!!!!
	if string.find(vb, "%[") then
		processmore_table[ib] = {true,1}											-- TAG AS MULTIBAR IN this TABLE
	elseif string.find(vb, "Â") then
		processmore_table[ib] = {false,0}											-- A) SECTION HEADER - NOT A MEASURE
	elseif string.find(vb, "Å") then
		processmore_table[ib] = {false,0}											-- B) SECTION HEADER - NOT A MEASURE	
	else
		processmore_table[ib] = {false,1}											-- TAG AS A SINGLE BAR
	end
		--reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
end



for ipm,vpm in pairs(processmore_table) do		-- !!!!!!!!!!!!!!!!!!!!!!!!!!!!!    DEAL WITH ALL THE MULTIBARS     !!!!!!!
barmultiplier = 0
	if processmore_table[ipm][1] then
		if string.sub(BIAB_main_bars_table[ipm],1,1) ~= "[" then				-- 	CHECK TO SEE IF MULTIBAR
			if string.find(BIAB_main_bars_table[ipm],":") then
				startsbrace,endbrace = string.find(BIAB_main_bars_table[ipm],"%[",1)
				--reaper.ShowConsoleMsg(startsbrace.."\n")
				barmultiplier = tonumber(string.sub(BIAB_main_bars_table[ipm],1,startsbrace-1))
				if barmultiplier ~= nil and barmultiplier ~= 1 then				-- MULTIBAR WITH MULTI CHORDS = BAD
					if warned == false then
						biab_ex_warning = biab_ex_warning .. '- Multibars with more than one chord are not supported in BIAB export\nbecause they easily result in rhythms BIAB can not accept as input.\nThese measures have been rendered as "1.d" which will sound drums only\nallowing you to find and adjust them.\n\n'
						warned = true
					end
					newtablevalue = "1.d"
					for count = 1,barmultiplier-1,1 do
						newtablevalue = newtablevalue .. " | "
					end
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = barmultiplier
				elseif  barmultiplier ~= nil and barmultiplier == 1 then   -- THERE IS A 1 MULTIBAR - JUST REMOVE MULTI
				
					newtablevalue = string.sub(BIAB_main_bars_table[ipm],startsbrace + 1, string.len(BIAB_main_bars_table[ipm])-1)
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1	
				else												-- LIKELY USER SCREW UP NON NUMBER MULTIBAR ie G[2m 5]
					biab_ex_warning = biab_ex_warning .. '- Looks like your chord entry has formatting error.\nIt has been rendered as "1b.d" so you can find and manually adjust the error.'
					newtablevalue = "1b.d"
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1
				end
				
			else																-- ONLY ONE INTERNAL CHORD ALL GOOD
				startsbrace,endbrace = string.find(BIAB_main_bars_table[ipm],"%[",1)
				--reaper.ShowConsoleMsg(startsbrace.."\n")
				barmultiplier = tonumber(string.sub(BIAB_main_bars_table[ipm],1,startsbrace-1))
				if  barmultiplier ~= nil and barmultiplier == 1 then   -- THERE IS A 1 MULTIBAR - JUST REMOVE MULTI
					newtablevalue = string.sub(BIAB_main_bars_table[ipm],startsbrace + 1, string.len(BIAB_main_bars_table[ipm])-1)
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1
					
					
					
				elseif barmultiplier ~= nil then   ---!!!!!!!!!!!!!!!!!!! THIS WORKS BUT SHOULDN'T !!! WHY ???????????
					newtablevalue = string.sub(BIAB_main_bars_table[ipm],startsbrace, string.len(BIAB_main_bars_table[ipm])-1)
					for count = 1,barmultiplier-1,1 do
						newtablevalue = newtablevalue .. " | "
					end
					processmore_table[ipm][2] = barmultiplier				
				else								-- LIKELY USER ERROR - ONLY 1 INTERNAL CHORD, BUT BAD MULTI ie G[4]
					biab_ex_warning = biab_ex_warning .. '- Looks like your chord entry has formatting error.\nIt has been rendered as ' .. string.sub(BIAB_main_bars_table[ipm],startsbrace+1,string.len(BIAB_main_bars_table[ipm])-1) .. ' so you can find and manually adjust the error.\n'
					newtablevalue = string.sub(BIAB_main_bars_table[ipm],startsbrace+1,string.len(BIAB_main_bars_table[ipm])-1)
					processmore_table[ipm][1] = false
					processmore_table[ipm][2] = 1
				end
			end
			BIAB_main_bars_table[ipm] = newtablevalue
		end
	--reaper.ShowConsoleMsg(tostring(processmore_table[ib][1]).."\n")
	end
end
biab_measurecount_total = 0						-- LABEL ALL THE MEASURES ACCORDING TO THEIR MEASURE NUMBER 
for i,v in pairs(processmore_table) do
	biab_measurecount_total = biab_measurecount_total + processmore_table[i][2]
	processmore_table[i][3] = biab_measurecount_total
end




in_item_table = {}					--  !!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!! DEAL WITH BRACED MEASURE INTERNALS
for i,v in pairs(processmore_table) do
	if processmore_table[i][1] then
		inmeasure_table = Split(string.sub(BIAB_main_bars_table[i],2,string.len(BIAB_main_bars_table[i])-1), ":")
		--reaper.ShowConsoleMsg(string.sub(BIAB_main_bars_table[i],2,string.len(BIAB_main_bars_table[i])-1) .. "\n")
		buileroo = ""
		split_mult_total = 0
		chord_count_total = 0
			in_item_table = {}		
		for ibt,vbt in pairs(inmeasure_table) do
			chord_count_total = chord_count_total + 1		

		
			item_split_starter,item_split_ender = string.find(vbt, "%(",1)	
			if item_split_starter ~= nil then
				--reaper.ShowConsoleMsg("found it\n")
				split_mult = tonumber(string.sub(vbt,1,item_split_starter-1))
				split_mult_total = split_mult_total + split_mult
				in_item_table[ibt] = {split_mult, string.sub(vbt,item_split_starter + 1,string.len(vbt) - 1)}
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")				
			else
				--reaper.ShowConsoleMsg("nope\n")	
				split_mult = 1				
				split_mult_total = split_mult_total + split_mult
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. ' string = ' .. string.sub(vbt,1,string.len(vbt)) .. "\n")
				in_item_table[ibt] = {1,vbt}
				--reaper.ShowConsoleMsg("splitmult = ".. split_mult .. " SplitMult Total = " .. split_mult_total .. " Cell: " .. in_item_table[ibt][2] .. "\n")		
			end
		end
----------------------------------------------------------------------------------------
		
		for ig,vg in pairs(in_item_table) do
			addstart = 1
			if string.sub(vg[2],1,1) == " " then
				addstart = 2
			else
			end
			if string.sub(vg[2],addstart,addstart) == "^" then
				if string.sub(vg[2],addstart + 1 ,addstart + 1) == "^" then
					addstart = addstart + 2
				else
					addstart = addstart + 1
				end
			else
			end
			if string.sub(vg[2],addstart,addstart) == "b" or string.sub(vg[2],addstart,addstart) == "#" then
				addstart = addstart + 2
			else
				addstart = addstart + 1
			end
			endtype,_ = string.find(vg[2], "/")
			if endtype ~= nil then endtype = endtype - 1 end
			if endtype == nil then endtype,_ = string.find(string.sub(vg[2],2,string.len(vg[2]))," ") end
			if endtype == nil then endtype = string.len(vg[2]) end
				replacetype = string.sub(vg[2],addstart, endtype)
				--reaper.ShowConsoleMsg(replacetype .. "\n")
			if musictheory.to_biab_translation[replacetype] ~= nil then
				in_item_table[ig][2] = string.sub(vg[2],1,addstart-1) .. musictheory.to_biab_translation[replacetype] .. string.sub(vg[2],endtype + 1, string.len(vg[2]))
			end
		end
		
		
		
		
		
----------------------------------------------------------------------------------------		
		if chord_count_total == 1 then
			buileroo = in_item_table[1][2] .. " "
			
		
		elseif chord_count_total == 2 and in_item_table[1][1] == in_item_table[2][1] then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 3 and tonumber(in_item_table[2][1]) == 1 then
			buileroo = in_item_table[1][2] .. " / / " .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 3 then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / / "
		elseif chord_count_total == 2 and in_item_table[1][1] > in_item_table[2][1] then
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. BIAB_main_bars_table[i] .. ' may have been simplified.\n'
			buileroo = in_item_table[1][2] .. " / / " .. in_item_table[2][2] .. " "
		elseif chord_count_total == 2 and in_item_table[1][1] < in_item_table[2][1] then
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. BIAB_main_bars_table[i] .. ' may have been simplified.\n'
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / / "			

		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 2 and tonumber(in_item_table[2][1]) == 1 and tonumber(in_item_table[3][1]) == 1 then
			buileroo = in_item_table[1][2] .. " / " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 1 and tonumber(in_item_table[3][1]) == 2 then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " / "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) == 1 and tonumber(in_item_table[2][1]) == 2 and tonumber(in_item_table[3][1]) == 1 then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / " .. in_item_table[3][2] .. " "
		elseif chord_count_total == 3 and tonumber(in_item_table[1][1]) > tonumber(in_item_table[2][1]) and tonumber(in_item_table[1][1]) > tonumber(in_item_table[3][1]) then
			buileroo = in_item_table[1][2] .. " / " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " "
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. BIAB_main_bars_table[i] .. ' may have been simplified.\n'			
		elseif chord_count_total == 3 and tonumber(in_item_table[3][1]) > tonumber(in_item_table[1][1]) and tonumber(in_item_table[3][1]) > tonumber(in_item_table[2][1]) then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " / "
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. BIAB_main_bars_table[i] .. ' may have been simplified.\n'			
		elseif chord_count_total == 3 and tonumber(in_item_table[2][1]) > tonumber(in_item_table[1][1]) and tonumber(in_item_table[2][1]) > tonumber(in_item_table[3][1]) then
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. '\n' .. BIAB_main_bars_table[i] .. ' may have been simplified.\n'		
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " / " .. in_item_table[3][2] .. " "
			
		elseif chord_count_total == 4 and tonumber(in_item_table[1][1]) == tonumber(in_item_table[2][1]) and  tonumber(in_item_table[1][1]) == tonumber(in_item_table[3][1]) and tonumber(in_item_table[1][1]) == tonumber(in_item_table[4][1]) then
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " " .. in_item_table[4][2] .. " "

		elseif chord_count_total == 4 and split_mult_total > 4 then
			biab_ex_warning = biab_ex_warning .. '- Around measure '  .. processmore_table[i][3] .. ' ' .. '\nthe rhythm of chords ' .. BIAB_main_bars_table[i] .. '\n was simplified due to BIAB limititations.\n'
			buileroo = in_item_table[1][2] .. " " .. in_item_table[2][2] .. " " .. in_item_table[3][2] .. " " .. in_item_table[4][2] .. " "
			
		elseif chord_count_total > 4 then
			biab_ex_warning = biab_ex_warning .. '- Around measure ' .. processmore_table[i][3] .. ' ' .. BIAB_main_bars_table[i] .. '\nonly the chords ' .. in_item_table[1][2] .. ' ' .. in_item_table[2][2] .. ' ' .. in_item_table[3][2] .. ' ' .. in_item_table[4][2] .. '\n could be rendered due to BIAB limit of 4 chords per bar.\n'
			buileroo = in_item_table[1][2] .. ' ' .. in_item_table[2][2] .. ' ' .. in_item_table[3][2] .. ' ' .. in_item_table[4][2] .. " "
			
		else
			buileroo = BIAB_main_bars_table[i]
		end
		
		BIAB_main_bars_table[i] = buileroo

	else
		this_single_chord = BIAB_main_bars_table[i]
		addstart = 1
		if string.sub(this_single_chord,1,1) == " " then
			addstart = 2
		else
		end
		if string.sub(this_single_chord,addstart,addstart) == "^" then
			if string.sub(this_single_chord,addstart + 1 ,addstart + 1) == "^" then
				addstart = addstart + 2
			else
				addstart = addstart + 1
			end
		else
		end
		if string.sub(this_single_chord,addstart,addstart) == "b" or string.sub(this_single_chord,addstart,addstart) == "#" then
			addstart = addstart + 2
		else
			addstart = addstart + 1
		end
		endtype,_ = string.find(this_single_chord, "/")
		if endtype ~= nil then endtype = endtype - 1 end
		if endtype == nil then endtype,_ = string.find(string.sub(this_single_chord,2,string.len(this_single_chord))," ") end
		if endtype == nil then endtype = string.len(this_single_chord) end
		replacetype = string.sub(this_single_chord,addstart, endtype)
		--reaper.ShowConsoleMsg(replacetype .. "\n")
		if musictheory.to_biab_translation[replacetype] ~= nil then
			BIAB_main_bars_table[i] = string.sub(this_single_chord,1,addstart-1) .. musictheory.to_biab_translation[replacetype] .. string.sub(this_single_chord,endtype + 1, string.len(this_single_chord))
		end
	end

end




for i,v in pairs(BIAB_main_bars_table) do							--	DEAL WITH REPEATS ON THE WAY TO TEXT
	if v == "!Repeat!" then
	BIAB_post_table_chord_data = BIAB_post_table_chord_data .. " | "  .. the_last_BIAB_bar_content
	else
	BIAB_post_table_chord_data = BIAB_post_table_chord_data .. " | "  .. v
	the_last_BIAB_bar_content = v
	end
end
																					
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "| Â |", "|A) ")		-- SWAP OUT FOR A)
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "| Å |", "|B) ")			-- AND B) SECTION MARKS
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "<<", "^^")			-- SWAP OUT FOR 16th 
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "<", "^")					-- AND 8th PUSHES IN BIAB FORMAT

BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b1", " 1b")			-- SWAP OUT ROOTS TO BIAB STYLE
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b2", " 2b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b3", " 3b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b4", " 4b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b5", " 5b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b6", " 6b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, " b7", " 7b")

BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b1", "/1b")			-- SWAP OUT BASS TO BIAB STYLE
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b2", "/2b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b3", "/3b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b4", "/4b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b5", "/5b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b6", "/6b")
BIAB_post_table_chord_data = string.gsub(BIAB_post_table_chord_data, "/b7", "/7b")

the_BIAB_bar_count = 0
--reaper.ShowConsoleMsg("\n-----------------------------------------\n")
for i,v in pairs(processmore_table) do
	the_BIAB_bar_count = the_BIAB_bar_count + tonumber(processmore_table[i][2])
	--reaper.ShowConsoleMsg("COUNT = " .. tonumber(processmore_table[i][2]) .. "TOTAL = " .. the_BIAB_bar_count .. "\n")
end
return BIAB_post_table_chord_data, the_BIAB_bar_count, thefail
end

function Split(s, delimiter)
    result = {};
    for match in (s..delimiter):gmatch("(.-)"..delimiter) do
        table.insert(result, match);
    end
    return result;
end




---------------------------------------------------------Swap out sets of unequal lenght items
-- \\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\\
function Swapout(haystack, needletable)
	for swap_i, swap_v in pairs(needletable) do
	::keepswapping::																	-- CONVERT TABS TO SPACES
	local current_text_length = string.len(haystack)
	haystack = string.gsub(haystack, swap_v[1] , swap_v[2])
		if current_text_length ~= string.len(haystack) then
		goto keepswapping
		end
	end
	return haystack
end



--  Write to Console - Commented out for general user runtime - Turn on to Debug
function Show_To_User(to_user_message)
    --reaper.ShowConsoleMsg(to_user_message)
end

--  Write to Console - Commented out unless debugging
function Show_To_Dev(to_dev_message)
    --reaper.ShowConsoleMsg(to_dev_message)
end


--  A function that returns every value of a table as text - NOT ORIGINAL WORK
function Table_Print (tbl, indent) 
  if not indent then indent = 0 end
  local toprint = string.rep(" ", indent) .. "{\r\n"
  indent = indent + 2 
  for k, v in pairs(tbl) do
    toprint = toprint .. string.rep(" ", indent)
    if (type(k) == "number") then
      toprint = toprint .. "[" .. k .. "] = "
    elseif (type(k) == "string") then
      toprint = toprint  .. k ..  "= "   
    end
    if (type(v) == "number") then
      toprint = toprint .. v .. ",\r\n"
    elseif (type(v) == "string") then
      toprint = toprint .. "\"" .. v .. "\",\r\n"
    elseif (type(v) == "table") then
      toprint = toprint .. Table_Print(v, indent + 2) .. ",\r\n"
    else
      toprint = toprint .. "\"" .. tostring(v) .. "\",\r\n"
    end
  end
  toprint = toprint .. string.rep(" ", indent-2) .. "}"
  return toprint
end


--  A pair of functions that return convert decimals to fractions - NOT ORIGINAL WORK

function Provide_Fraction(numer,denom)
	fracttop, fractbottom = Convert_Decimal_To_Fraction(numer)
	if fractbottom == 1 then
	fractiontoreturn = fracttop
	else
	fractiontoreturn = string.format("%d/%d",fracttop, fractbottom)
	end
   return fractiontoreturn
end


function Convert_Decimal_To_Fraction(num)
   local W = math.floor(num)
   local F = num - W
   local pn, n, N = 0, 1
   local pd, d, D = 1, 0
   local x, err, q, Q
   repeat
      x = x and 1 / (x - q) or F
      q, Q = math.floor(x), math.floor(x + 0.5)
      pn, n, N = n, q*n + pn, Q*n + pn
      pd, d, D = d, q*d + pd, Q*d + pd
      err = F - N/D
   until math.abs(err) < 1e-15
   return N + D*W, D, err
end


-- _______________________________________________________________________ MAIN FUNCTION  ____________________
Initialize_Track_Setup()
IM_GUI_Loop()

