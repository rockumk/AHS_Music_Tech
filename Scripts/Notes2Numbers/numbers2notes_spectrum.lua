-- @description numbers2notes_spectrum
-- @version 1.0.3
-- @noindex
-- @author Rock Kennedy
-- @about
--   # numbers2notes_spectrum
--   Numbers2Notes Support File for generating full-spectrum chord grids.
-- @changelog
--   # Fixes
--   + CRITICAL: Removed recursive logic that caused Stack Overflow crashes on long tracks.
--   + Optimization: Added MIDI_DisableSort for significantly faster generation.
--   + Localized variables to prevent global leaks.

local spectrum = {
    make_full_spectrum = function(grid_track)
        
        -- 1. Setup Local Variables
        local theWholeTable = {}
        local focusedtake = grid_track
        
        -- 2. Count how many notes are in the item currently
        local _, noteCount, _, _ = reaper.MIDI_CountEvts(focusedtake)

        -- 3. Collect all notes (Using a Loop, not Recursion)
        for i = 0, noteCount - 1 do
            local retval, selected, muted, startppq, endppq, chan, pitch, vel = reaper.MIDI_GetNote(focusedtake, i)
            if retval then
                -- Store note data in a table
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

        -- 4. Delete all original notes
        -- We do this backwards so deleting note #0 doesn't change the index of note #1
        for i = noteCount - 1, 0, -1 do
            reaper.MIDI_DeleteNote(focusedtake, i)
        end

        -- 5. Generate the Spectrum (Insert copies across octaves)
        reaper.MIDI_DisableSort(focusedtake) -- Disable sorting for speed while inserting
        
        for _, noteData in ipairs(theWholeTable) do
            -- Calculate the note class (0-11, e.g., C=0, C#=1)
            local base_pitch_class = noteData.pitch % 12
            
            -- Loop through MIDI range (0 to 127) to fill octaves
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
                    false -- noSort (we sort at the very end)
                )
                current_pitch = current_pitch + 12 -- Jump up one octave
            end
        end

        reaper.MIDI_Sort(focusedtake) -- Re-sort once at the end
        return "spectrumdone"
    end
}

return spectrum