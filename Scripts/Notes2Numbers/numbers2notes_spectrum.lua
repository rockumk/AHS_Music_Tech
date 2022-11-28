-- @description numbers2notes_spectrum
-- @version 1.0.1
-- @author Rock Kennedy
-- @about
--   # numbers2notes_spectrum
--   Numbers2Notes Support File.
-- @changelog
--   Name Change
local spectrum = {
make_full_spectrum = function(grid_track)
--reaper.ShowConsoleMsg("MADE IT!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!")

--  ----------------------------------------     VARIABLES




noteIndex = 0
noteExists = 1
noteIsSelected = 1
noteIsmuted = 0
theStartppqpos = 0
theEndppqpos = 0
theChan = 1
thePitch = 1
theVel = 127
OneNoteDataRow = {}
theWholeTable = {""}
--  ----------------------------------------    FUNCTION LIST

--COLLECT ALL THE CURRENT NOTE DATA
function GettheNotes()
noteExists, noteIsSelected, noteIsmuted, theStartppqpos, theEndppqpos, theChan, thePitch, theVel = reaper.MIDI_GetNote(focusedtake, noteIndex)
if noteExists then
OneNoteDataRow = ""
OneNoteDataRow = {noteExists, noteIsSelected, noteIsmuted, theStartppqpos, theEndppqpos, theChan, thePitch, theVel}
theWholeTable[#theWholeTable+1] = OneNoteDataRow
--msg("The Note = "..tostring(thePitch).." "..tostring(theVel))
noteIndex = noteIndex +1
GettheNotes()
else 
end
end

--  -------------------------------------------- PROGRAM ! ! !
--  SAVE THE DATA ON THE NOTES IN A TABLE

focusedtake = grid_track
--msg(tostring(focusedtake))
reaper.MIDI_DisableSort(focusedtake)
GettheNotes()


--  DELETE THE NOTES
for i=#theWholeTable,1,-1 do  
reaper.MIDI_DeleteNote( focusedtake, i-1 )
end

--  PUT IN ALL THE COPIES
for i=1,#theWholeTable,1 do 
if theWholeTable[i][1] == true then
theModulus = theWholeTable[i][7]%12
while theModulus <= 127 do
reaper.MIDI_InsertNote( focusedtake, 0, 0, theWholeTable[i][4], theWholeTable[i][5], theWholeTable[i][6], theModulus, theWholeTable[i][8], 0 )
theModulus = theModulus +12
end
else
end
end

reaper.MIDI_Sort(focusedtake)
return "spectrumdone"
end
}

return spectrum



