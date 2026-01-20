-- @description numbers2notes_spectrum
-- @version 1.0.8
-- @author Rock Kennedy
-- @about Numbers2Notes Support File for generating full-spectrum chord grids.
-- @changelog
--   + SPEED FIX: Re-enabled MIDI_DisableSort during generation to fix "Script running too long".
--   + RELIABILITY: Reverted to CountEvts (post-sort) to ensure all notes are captured.

local spectrum = {
    make_full_spectrum = function(grid_track)
        
        -- SAFETY CHECK
        if not grid_track or not reaper.ValidatePtr(grid_track, "MediaItem_Take*") then 
            return "spectrum_skipped"
        end

        local theWholeTable = {}
        local focusedtake = grid_track
        
        -- 1. SORT & COUNT (Crucial Step)
        -- We must sort first because the main script inserted Groove notes out of order.
        reaper.MIDI_Sort(focusedtake)
        local _, noteCount, _, _ = reaper.MIDI_CountEvts(focusedtake)

        -- 2. READ NOTES
        -- We use a standard for-loop based on Count. 
        -- Since we sorted, indices 0 to count-1 are guaranteed to exist.
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

        -- 3. DELETE ORIGINALS
        -- Delete backwards to maintain index integrity
        for i = noteCount - 1, 0, -1 do
            reaper.MIDI_DeleteNote(focusedtake, i)
        end

        -- 4. GENERATE SPECTRUM (Fast Mode)
        -- Disable sorting so Reaper doesn't recalculate the list 5,000 times
        reaper.MIDI_DisableSort(focusedtake) 
        
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
                    false -- noSort=false (We disabled it globally above)
                )
                current_pitch = current_pitch + 12 
            end
        end

        -- 5. FINAL SORT
        -- Re-enable sorting and clean up
        reaper.MIDI_Sort(focusedtake) 
        
        return "spectrumdone"
    end
}

return spectrum
