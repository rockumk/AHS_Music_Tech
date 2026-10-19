-- @description LaunchpadSystemLib
-- @author Rock Kennedy
-- @version 7.0
-- @about
--   Contains some of the Launchpad Xtra's Underlying Structure


local Lpxlib = {}  -- the module/library table

--[[
  ReaScript Name: 9x9 Grid Example with Background Colors (0xRRGGBBAA)
  Author: Example
  Description: Demonstration of drawing a 9×9 grid in a ReaScript GUI, each cell has a custom color.
               Colors are provided in 0xRRGGBBAA format. Underscores in labels become linefeeds. 
               Text color is auto-chosen black or white based on brightness.
--]]

-------------------------------------
-- 1) The Helper Grid label data (9 lines, 9 columns each)
-------------------------------------

Lpxlib.grid_text_page_1 = [[
Scroll Down,Scroll Up,Go_Marker Left,Go_Marker Right,Save Project,Reserved,Reserved,Reserved,Page Status
1,2,3,4,5,Auto Crossfade,Item Grouping,Ripple,Fast Forward
6,7,8,9,10,Grid,Snap,Locking,Fast Reverse
11,12,13,14,15,Metronome,Go_to Master_FX,Loop,Scan Forward
16,17,18,19,20,Toggle Show Docker,Go_Next FX_Up,Toggle Show Library,Scan Backward
21,22,23,24,25,Go_Left Track_FX,Toggle Show_FX,Go_Right Track_FX,Toggle Show Mixer
26,27,28,29,30,Record,Go_Next FX_Down,Toggle Show This_Grid,Page_1
31,32,33,34,35,Save_Take,Restart Take,Cancel Take,Page_2
36,37,38,39,40,Play,Stop,Pause,Page_3
]]

Lpxlib.grid_text_page_2 = [[
Scroll Down,Scroll Up,Go_Marker Left,Go_Marker Right,Save Project,Reserved,Reserved,Reserved,Page Status
41,42,43,44,45,Auto Crossfade,Item Grouping,Ripple,Fast Forward
46,47,48,49,50,Grid,Snap,Locking,Fast Reverse
51,52,53,54,55,Metronome,Go_to Master_FX,Loop,Scan Forward
56,57,58,59,60,Toggle Show Docker,Go_Next FX_Up,Toggle Show Library,Scan Backward
61,62,63,64,65,Go_Left Track_FX,Toggle Show_FX,Go_Right Track_FX,Toggle Show Mixer
66,67,68,69,70,Record,Go_Next FX_Down,Toggle Show This_Grid,Page_1
71,72,73,74,75,Save_Take,Restart Take,Cancel Take,Page_2
76,77,78,79,80,Play,Stop,Pause,Page_3
]]

Lpxlib.grid_text_page_3 = [[
Scroll Down,Scroll Up,Go_Marker Left,Go_Marker Right,Save Project,Reserved,Reserved,Reserved,Page Status
81,82,83,84,85,Auto Crossfade,Item Grouping,Ripple,Fast Forward
86,87,88,89,90,Grid,Snap,Locking,Fast Reverse
91,92,93,94,95,Metronome,Go_to Master_FX,Loop,Scan Forward
96,97,98,99,100,Toggle Show Docker,Go_Next FX_Up,Toggle Show Library,Scan Backward
101,102,103,104,105,Go_Left Track_FX,Toggle Show_FX,Go_Right Track_FX,Toggle Show Mixer
106,107,108,109,110,Record,Go_Next FX_Down,Toggle Show This_Grid,Page_1
111,112,113,114,115,Save_Take,Restart Take,Cancel Take,Page_2
116,117,118,119,120,Play,Stop,Pause,Page_3
]]


-------------------------------------
-- 2) The color data (9 lines, 9 columns each), in 0xRRGGBBAA format
-------------------------------------


Lpxlib.grid_colors_page_1 = [[
0x61EEFFFF  0x61EEFFFF  0x61FFE9FF  0x61FFE9FF  0xEEEEEEFF  0xFFFF61FF  0xFFB361FF  0xFF6161FF  0xFF6161FF  
0xB36161FF  0xB36161FF  0xB36161FF  0xB36161FF  0xB36161FF  0x61FF61FF  0x61DD61FF  0x61B361FF  0x61EEFFFF  
0xB36161FF  0xB36161FF  0xB36161FF  0xB36161FF  0xB36161FF  0x61FFCCFF  0x61DDA1FF  0x61B381FF  0x61EEFFFF  
0xB37661FF  0xB37661FF  0xB37661FF  0xB37661FF  0xB37661FF  0x61EEFFFF  0x61C7DDFF  0x61A1B3FF  0x61FFE9FF  
0xB37661FF  0xB37661FF  0xB37661FF  0xB37661FF  0xB37661FF  0xCC61FCFF  0x555555FF  0x61A1FFFF  0x61FFE9FF  
0xB3B261FF  0xB3B261FF  0xB3B261FF  0xB3B261FF  0xB3B261FF  0x555555FF  0xDD61DDFF  0x555555FF  0xEEEEEEFF  
0xB3B261FF  0xB3B261FF  0xB3B261FF  0xB3B261FF  0xB3B261FF  0xDD6161FF  0x555555FF  0xCC61FCFF  0xFF6161FF  
0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61A1DDFF  0x8161DDFF  0xA1A1A1FF  0xFFB361FF  
0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61B36BFF  0x61FFE9FF  0xFF6161FF  0xFFB361FF  0xFFFF61FF  
]]

Lpxlib.grid_colors_page_2 = [[
0x61EEFFFF  0x61EEFFFF  0x61FFE9FF  0x61FFE9FF  0xEEEEEEFF  0xFFFF61FF  0xFFB361FF  0xFF6161FF  0xFF6161FF  
0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61FF61FF  0x61DD61FF  0x61B361FF  0x61EEFFFF  
0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61A1DDFF  0x61FFCCFF  0x61DDA1FF  0x61B381FF  0x61EEFFFF  
0x8161DDFF  0x8161DDFF  0x8161DDFF  0x8161DDFF  0x8161DDFF  0x61EEFFFF  0x61C7DDFF  0x61A1B3FF  0x61FFE9FF  
0x8161DDFF  0x8161DDFF  0x8161DDFF  0x8161DDFF  0x8161DDFF  0xCC61FCFF  0x555555FF  0x61A1FFFF  0x61FFE9FF  
0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0x555555FF  0xDD61DDFF  0x555555FF  0xEEEEEEFF  
0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0xDD61A1FF  0xDD6161FF  0x555555FF  0xCC61FCFF  0xFF6161FF  
0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0x61A1DDFF  0x8161DDFF  0xA1A1A1FF  0xFFB361FF  
0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0xDDDDDDFF  0x61FFE9FF  0xFF6161FF  0xFFB361FF  0xFFFF61FF  
]]
 
Lpxlib.grid_colors_page_3 = [[
0x61EEFFFF  0x61EEFFFF  0x61FFE9FF  0x61FFE9FF  0xEEEEEEFF  0xFFFF61FF  0xFFB361FF  0xFF6161FF  0xFF6161FF  
0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0x61FF61FF  0x61DD61FF  0x61B361FF  0x61EEFFFF  
0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0xFFB3B3FF  0x61FFCCFF  0x61DDA1FF  0x61B381FF  0x61EEFFFF  
0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0x61EEFFFF  0x61C7DDFF  0x61A1B3FF  0x61FFE9FF  
0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0xF9BA76FF  0xCC61FCFF  0x555555FF  0x61A1FFFF  0x61FFE9FF  
0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0x555555FF  0xDD61DDFF  0x555555FF  0xEEEEEEFF  
0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0xFFEEA1FF  0xDD6161FF  0x555555FF  0xCC61FCFF  0xFF6161FF  
0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0x61A1DDFF  0x8161DDFF  0xA1A1A1FF  0xFFB361FF  
0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0xB3FFA1FF  0x61FFE9FF  0xFF6161FF  0xFFB361FF  0xFFFF61FF  
]]
 

-- No longer used, but saved in case.
Lpxlib.HexChart = {
"F0 00 20 29 02 0C 03 ",

"02 5B 22 ",
"00 5C 22 ",
"00 5D 00 ",
"00 5E 00 ",
"00 5F 00 ",
"00 60 00 ",
"00 61 00 ",
"00 62 00 ",
"00 63 00 ",
"00 64 22 ",

"00 51 15 ",
"00 52 15 ",
"00 53 15 ",
"00 54 15 ",
"00 55 15 ",
"00 56 00 ",
"00 57 00 ",
"00 58 00 ",
"00 59 00 ",
"00 60 00 ",

"00 47 15 ",
"00 48 15 ",
"00 49 15 ",
"00 4A 15 ",
"00 4B 15 ",
"00 4C 00 ",
"00 4D 00 ",
"00 4E 00 ",
"00 4F 00 ",
"00 50 00 ",

"00 3D 61 ",
"00 3E 61 ",
"00 3F 61 ",
"00 40 61 ",
"00 41 61 ",
"00 42 00 ",
"00 43 00 ",
"00 44 00 ",
"00 45 00 ",
"00 46 00 ",

"00 33 61 ",
"00 34 61 ",
"00 35 61 ",
"00 36 61 ",
"00 37 61 ",
"00 38 00 ",
"00 39 00 ",
"00 3A 00 ",
"00 3B 00 ",
"00 3C 00 ",

"00 29 54 ",
"00 2A 54 ",
"00 2B 54 ",
"00 2C 54 ",
"00 2D 54 ",
"00 2E 00 ",
"00 2F 00 ",
"00 30 00 ",
"00 31 00 ",
"00 32 00 ",

"00 1F 54 ",
"00 20 54 ",
"00 21 54 ",
"00 22 54 ",
"00 23 54 ",
"00 24 00 ",
"00 25 00 ",
"00 26 00 ",
"00 27 00 ",
"00 28 00 ",

"00 15 05 ",
"00 16 05 ",
"00 17 05 ",
"00 18 05 ",
"00 19 05 ",
"00 1A 00 ",
"00 1B 00 ",
"00 1C 00 ",
"00 1D 00 ",
"00 1E 00 ",

"00 0B 05 ",
"00 0C 05 ",
"00 0D 05 ",
"00 0E 05 ",
"00 0F 05 ",
"00 10 00 ",
"00 11 00 ",
"00 12 22 ",
"00 13 00 ",
"00 14 00 ",

"F7"}






Lpxlib.pad_types = {


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",


" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 ",
" 00 "

}


Lpxlib.pad_addresses = {


" 5B ",
" 5C ",
" 5D ",
" 5E ",
" 5F ",
" 60 ",
" 61 ",
" 62 ",
" 63 ",


" 51 ",
" 52 ",
" 53 ",
" 54 ",
" 55 ",
" 56 ",
" 57 ",
" 58 ",
" 59 ",


" 47 ",
" 48 ",
" 49 ",
" 4A ",
" 4B ",
" 4C ",
" 4D ",
" 4E ",
" 4F ",


" 3D ",
" 3E ",
" 3F ",
" 40 ",
" 41 ",
" 42 ",
" 43 ",
" 44 ",
" 45 ",


" 33 ",
" 34 ",
" 35 ",
" 36 ",
" 37 ",
" 38 ",
" 39 ",
" 3A ",
" 3B ",


" 29 ",
" 2A ",
" 2B ",
" 2C ",
" 2D ",
" 2E ",
" 2F ",
" 30 ",
" 31 ",


" 1F ",
" 20 ",
" 21 ",
" 22 ",
" 23 ",
" 24 ",
" 25 ",
" 26 ",
" 27 ",


" 15 ",
" 16 ",
" 17 ",
" 18 ",
" 19 ",
" 1A ",
" 1B ",
" 1C ",
" 1D ",


" 0B ",
" 0C ",
" 0D ",
" 0E ",
" 0F ",
" 10 ",
" 11 ",
" 12 ",
" 13 "

}

Lpxlib.pad_colors1 = {


" 25 ",
" 25 ",
" 21 ",
" 21 ",
" 03 ",
" 0D ",
" 09 ",
" 05 ",
" 05 ",


" 07 ",
" 07 ",
" 07 ",
" 07 ",
" 07 ",
" 15 ",
" 16 ",
" 17 ",
" 25 ",


" 07 ",
" 07 ",
" 07 ",
" 07 ",
" 07 ",
" 1D ",
" 1E ",
" 1F ",
" 25 ",


" 0B ",
" 0B ",
" 0B ",
" 0B ",
" 0B ",
" 25 ",
" 26 ",
" 27 ",
" 21 ",


" 0B ",
" 0B ",
" 0B ",
" 0B ",
" 0B ",
" 51 ",
" 00 ",
" 4F ",
" 21 ",


" 0F ",
" 0F ",
" 0F ",
" 0F ",
" 0F ",
" 00 ",
" 36 ",
" 00 ",
" 03 ",


" 0F ",
" 0F ",
" 0F ",
" 0F ",
" 0F ",
" 6A ",
" 00 ",
" 51 ",
" 05 ",


" 1B ",
" 1B ",
" 1B ",
" 1B ",
" 1B ",
" 2A ",
" 32 ",
" 75 ",
" 09 ",


" 1B ",
" 1B ",
" 1B ",
" 1B ",
" 1B ",
" 21 ",
" 05 ",
" 09 ",
" 0D "

}




Lpxlib.pad_colors2 = {


" 25 ",
" 25 ",
" 21 ",
" 21 ",
" 03 ",
" 0D ",
" 09 ",
" 05 ",
" 09 ",


" 2A ",
" 2A ",
" 2A ",
" 2A ",
" 2A ",
" 15 ",
" 16 ",
" 17 ",
" 25 ",


" 2A ",
" 2A ",
" 2A ",
" 2A ",
" 2A ",
" 1D ",
" 1E ",
" 1F ",
" 25 ",


" 32 ",
" 32 ",
" 32 ",
" 32 ",
" 32 ",
" 25 ",
" 26 ",
" 27 ",
" 21 ",


" 32 ",
" 32 ",
" 32 ",
" 32 ",
" 32 ",
" 51 ",
" 00 ",
" 4F ",
" 21 ",


" 3A ",
" 3A ",
" 3A ",
" 3A ",
" 3A ",
" 00 ",
" 36 ",
" 00 ",
" 03 ",


" 3A ",
" 3A ",
" 3A ",
" 3A ",
" 3A ",
" 6A ",
" 00 ",
" 51 ",
" 05 ",


" 02 ",
" 02 ",
" 02 ",
" 02 ",
" 02 ",
" 2A ",
" 32 ",
" 75 ",
" 09 ",


" 02 ",
" 02 ",
" 02 ",
" 02 ",
" 02 ",
" 21 ",
" 05 ",
" 09 ",
" 0D "

}


Lpxlib.pad_colors3 = {


" 25 ",
" 25 ",
" 21 ",
" 21 ",
" 03 ",
" 0D ",
" 09 ",
" 05 ",
" 0D ",


" 04 ",
" 04 ",
" 04 ",
" 04 ",
" 04 ",
" 15 ",
" 16 ",
" 17 ",
" 25 ",


" 04 ",
" 04 ",
" 04 ",
" 04 ",
" 04 ",
" 1D ",
" 1E ",
" 1F ",
" 25 ",


" 6C ",
" 6C ",
" 6C ",
" 6C ",
" 6C ",
" 25 ",
" 26 ",
" 27 ",
" 21 ",


" 6C ",
" 6C ",
" 6C ",
" 6C ",
" 6C ",
" 51 ",
" 00 ",
" 4F ",
" 21 ",


" 0C ",
" 0C ",
" 0C ",
" 0C ",
" 0C ",
" 00 ",
" 36 ",
" 00 ",
" 03 ",


" 0C ",
" 0C ",
" 0C ",
" 0C ",
" 0C ",
" 6A ",
" 00 ",
" 51 ",
" 05 ",


" 58 ",
" 58 ",
" 58 ",
" 58 ",
" 58 ",
" 2A ",
" 32 ",
" 75 ",
" 09 ",



" 58 ",
" 58 ",
" 58 ",
" 58 ",
" 58 ",
" 21 ",
" 05 ",
" 09 ",
" 0D "

}

Lpxlib.six4add = {


" 51 ",
" 52 ",
" 53 ",
" 54 ",
" 55 ",
" 56 ",
" 57 ",
" 58 ",



" 47 ",
" 48 ",
" 49 ",
" 4A ",
" 4B ",
" 4C ",
" 4D ",
" 4E ",



" 3D ",
" 3E ",
" 3F ",
" 40 ",
" 41 ",
" 42 ",
" 43 ",
" 44 ",



" 33 ",
" 34 ",
" 35 ",
" 36 ",
" 37 ",
" 38 ",
" 39 ",
" 3A ",



" 29 ",
" 2A ",
" 2B ",
" 2C ",
" 2D ",
" 2E ",
" 2F ",
" 30 ",



" 1F ",
" 20 ",
" 21 ",
" 22 ",
" 23 ",
" 24 ",
" 25 ",
" 26 ",



" 15 ",
" 16 ",
" 17 ",
" 18 ",
" 19 ",
" 1A ",
" 1B ",
" 1C ",



" 0B ",
" 0C ",
" 0D ",
" 0E ",
" 0F ",
" 10 ",
" 11 ",
" 12 ",


}

Lpxlib.cc = {
" 00 ",
" 01 ",
" 02 ",
" 03 ",
" 04 ",
" 05 ",
" 06 ",
" 07 ",
" 08 ",
" 09 ",
" 0A ",
" 0B ",
" 0C ",
" 0D ",
" 0E ",
" 0F ",
" 10 ",
" 11 ",
" 12 ",
" 13 ",
" 14 ",
" 15 ",
" 16 ",
" 17 ",
" 18 ",
" 19 ",
" 1A ",
" 1B ",
" 1C ",
" 1D ",
" 1E ",
" 1F ",
" 20 ",
" 21 ",
" 22 ",
" 23 ",
" 24 ",
" 25 ",
" 26 ",
" 27 ",
" 28 ",
" 29 ",
" 2A ",
" 2B ",
" 2C ",
" 2D ",
" 2E ",
" 2F ",
" 30 ",
" 31 ",
" 32 ",
" 33 ",
" 34 ",
" 35 ",
" 36 ",
" 37 ",
" 38 ",
" 39 ",
" 3A ",
" 3B ",
" 3C ",
" 3D ",
" 3E ",
" 3F ",
" 40 ",
" 41 ",
" 42 ",
" 43 ",
" 44 ",
" 45 ",
" 46 ",
" 47 ",
" 48 ",
" 49 ",
" 4A ",
" 4B ",
" 4C ",
" 4D ",
" 4E ",
" 4F ",
" 50 ",
" 51 ",
" 52 ",
" 53 ",
" 54 ",
" 55 ",
" 56 ",
" 57 ",
" 58 ",
" 59 ",
" 5A ",
" 5B ",
" 5C ",
" 5D ",
" 5E ",
" 5F ",
" 60 ",
" 61 ",
" 62 ",
" 63 ",
" 64 ",
" 65 ",
" 66 ",
" 67 ",
" 68 ",
" 69 ",
" 6A ",
" 6B ",
" 6C ",
" 6D ",
" 6E ",
" 6F ",
" 70 ",
" 71 ",
" 72 ",
" 73 ",
" 74 ",
" 75 ",
" 76 ",
" 77 ",
" 78 ",
" 79 ",
" 7A ",
" 7B ",
" 7C ",
" 7D ",
" 7E ",
" 7F ",
" 80 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 ",
" 01 "

}

return Lpxlib
