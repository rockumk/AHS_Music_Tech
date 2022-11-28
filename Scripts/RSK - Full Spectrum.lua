-- @description RSK_Full_Spectrum
-- @version 1.0.1
-- @author Rock Kennedy
-- @about
--   # RSK_Full_Spectrum
--   Duplicates all pitches at every octave.
-- @changelog
--   Name Change





------------------------------------------     VARIABLES
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
--JUST PRINT AND LINE RETURN MESSAGES
function msg(theMessage)
  messageWLF = theMessage.."\n"
  reaper.ShowConsoleMsg(messageWLF)
end


--COLLECT ALL THE CURRENT NOTE DATA
function GettheNotes()
noteExists, noteIsSelected, noteIsmuted, theStartppqpos, theEndppqpos, theChan, thePitch, theVel = reaper.MIDI_GetNote( focusedtake, noteIndex)
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
focusedEditorWin = reaper.MIDIEditor_GetActive()
focusedtake = reaper.MIDIEditor_EnumTakes(focusedEditorWin,0,1)
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
--msg("DATA = "..i..", "..tostring(theWholeTable[i][1])..", "..tostring(theWholeTable[i][2])..", "..tostring(theWholeTable[i][3])..", "..tostring(theWholeTable[i][7])..", "..tostring(theWholeTable[i][8]))
--msg("Modulus = "..theWholeTable[i][7]%12)
theModulus = theWholeTable[i][7]%12
while theModulus <= 127 do
reaper.MIDI_InsertNote( focusedtake, 0, 0, theWholeTable[i][4], theWholeTable[i][5], theWholeTable[i][6], theModulus, theWholeTable[i][8], 0 )
theModulus = theModulus +12
end
else
end
end



reaper.MIDI_Sort( focusedtake )

--[[











for i=2,#theWholeTable-1,1 do 
msg(tostring(i-1))
msg(tostring(theWholeTable[i][8]))
theModulus =(theWholeTable[i][8])%12
msg("the Modulus = "..theModulus)
end


for i=1, #theWholeTable, 1 do
if theWholeTable[i][2] then

reaper.MIDI_InsertNote( focusedtake, 0, 0, theWholeTable[i][4], theWholeTable[i][5], theWholeTable[i][6], theWholeTable[i][7]+12, theWholeTable[i][8], 0 )



end
end

--end
end






--]]


