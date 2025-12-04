-- @description RSK_Full_Spectrum
-- @version 1.0.2
-- @author Rock Kennedy
-- @about
--   # RSK_Full_Spectrum
--   Duplicates all pitches at every octave.
--   Run this from inside the MIDI Editor.
-- @changelog
--   + CRITICAL: Removed recursive logic that caused Stack Overflow crashes on long tracks.
--   + Optimization: Added MIDI_DisableSort for significantly faster generation.
--   + Safety: Localized all variables.

--  ----------------------------------------    MAIN LOGIC
local function main()
    -- 1. Get the Active Take from the MIDI Editor
    local focusedEditorWin = reaper.MIDIEditor_GetActive()
    if not focusedEditorWin then return end -- Exit if no editor is open
    
    local focusedtake = reaper.MIDIEditor_EnumTakes(focusedEditorWin, 0, 1)
    if not focusedtake or not reaper.ValidatePtr2(0, focusedtake, "MediaItem_Take*") then return end

    -- 2. Setup Variables
    local theWholeTable = {}
    
    -- 3. Count notes (Much faster than guessing)
    local _, noteCount = reaper.MIDI_CountEvts(focusedtake)

    -- 4. Collect all notes (Using a Loop, not Recursion)
    for i = 0, noteCount - 1 do
        local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(focusedtake, i)
        if retval then
            table.insert(theWholeTable, {
                selected = selected,
                muted = muted,
                start = startppq,
                ending = endppq,
                chan = chan,
                pitch = pitch,
                vel = vel
            })
        end
    end

    -- 5. Processing
    reaper.Undo_BeginBlock()
    reaper.MIDI_DisableSort(focusedtake) -- Disable sorting for speed

    -- Delete old notes (backwards loop)
    for i = noteCount - 1, 0, -1 do
        reaper.MIDI_DeleteNote(focusedtake, i)
    end

    -- Insert new copies across all octaves
    for _, noteData in ipairs(theWholeTable) do
        local base_pitch_class = noteData.pitch % 12
        local current_pitch = base_pitch_class
        
        while current_pitch <= 127 do
            reaper.MIDI_InsertNote(
                focusedtake, 
                noteData.selected, 
                noteData.muted, 
                noteData.start, 
                noteData.ending, 
                noteData.chan, 
                current_pitch, 
                noteData.vel, 
                false -- noSort
            )
            current_pitch = current_pitch + 12
        end
    end

    reaper.MIDI_Sort(focusedtake)
    reaper.Undo_EndBlock("RSK Full Spectrum Generate", -1)
end

-- Run the script
main()