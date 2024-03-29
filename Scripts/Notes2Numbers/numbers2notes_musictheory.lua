-- @description numbers2notes_musictheory
-- @version 1.0.1
-- @author Rock Kennedy
-- @about
--   # numbers2notes_musictheory
--   Numbers2Notes Support File.
-- @changelog
--   Name Change
local musictheory = {
key_table = {
["Ab"] = 8, 
["A"] = 9, 
["A#"] = 10, 
["Bb"] = 10, 
["B"] = 11, 
["C"] = 0, 
["C#"] = 1, 
["Db"] = 1, 
["D"] = 2, 
["D#"] = 3, 
["Eb"] = 3, 
["E"] = 4, 
["F"] = 5, 
["F#"] = 6, 
["Gb"] = 6, 
["G"] = 7, 
["G#"] = 8
},


letter_to_numbers = {
["Abb"] = 7,
["A##"] = 11, 
["Ab"] = 8,
["A#"] = 10, 
["A"] = 9,
["Bbb"] = 9,
["Bb"] = 10, 
["B#"] = 0, 
["B"] = 11, 
["Cb"] = 11, 
["C##"] = 2, 
["C#"] = 1, 
["C"] = 0, 
["Dbb"] = 0, 
["D##"] = 4, 
["Db"] = 1, 
["D#"] = 3, 
["D"] = 2, 
["Ebb"] = 2, 
["Eb"] = 3, 
["E#"] = 5, 
["E"] = 4, 
["Fb"] = 4, 
["F##"] = 7,
["F#"] = 6,
["F"] = 5, 
["Gbb"] = 5, 
["Gb"] = 6, 
["G##"] = 9,
["G#"] = 8,
["G"] = 7
},

full_letter_list = {
[0] = "Abb",
[1] = "A##",
[2] = "Ab",
[3] = "A#", 
[4] = "A",
[5] = "Bbb",
[6] = "Bb", 
[7] = "B#", 
[8] = "B", 
[9] = "Cb", 
[10] = "C##", 
[11] = "C#", 
[12] = "C", 
[13] = "Dbb", 
[14] = "D##", 
[15] = "Db", 
[16] = "D#", 
[17] = "D", 
[18] = "Ebb", 
[19] = "Eb", 
[20] = "E#", 
[21] = "E", 
[22] = "Fb", 
[23] = "F##",
[24] = "F#",
[25] = "F", 
[26] = "Gbb", 
[27] = "Gb", 
[28] = "G##",
[29] = "G#",
[30] = "G"
},


full_letter_list_set = {
[0] = {"Abb",7},
[1] = {"A##",11},
[2] = {"Ab",8},
[3] = {"A#",10},
[4] = {"A",9},
[5] = {"Bbb",9},
[6] = {"Bb",10},
[7] = {"B#",0},
[8] = {"B",11},
[9] = {"Cb",11},
[10] = {"C##",2},
[11] = {"C#",1},
[12] = {"C",0},
[13] = {"Dbb",0},
[14] = {"D##",4},
[15] = {"Db",1},
[16] = {"D#",3},
[17] = {"D",2}, 
[18] = {"Ebb",2},
[19] = {"Eb",3}, 
[20] = {"E#",5},
[21] = {"E",4},
[22] = {"Fb",4}, 
[23] = {"F##",7},
[24] = {"F#",6},
[25] = {"F",5},
[26] = {"Gbb",5}, 
[27] = {"Gb",6},
[28] = {"G##",9},
[29] = {"G#",8},
[30] = {"G",7},
},




is_it_flat_table = {
["Ab"] = true, 
["A"] = false, 
["A#"] = false, 
["Bb"] = true, 
["B"] = false, 
["C"] = true, 
["C#"] = false, 
["Db"] = true, 
["D"] = false, 
["D#"] = false, 
["Eb"] = true, 
["E"] = false, 
["F"] = true, 
["F#"] = false, 
["Gb"] = true, 
["G"] = false, 
["G#"] = false
},



sharps_table = {
[0] = "C",
[1] = "C#",
[2] = "D",
[3] = "D#",
[4] = "E",
[5] = "F",
[6] = "F#",
[7] = "G",
[8] = "G#",
[9] = "A",
[10] = "A#",
[11] = "B"
},

sharps_table2 = {
["0"] = "C",
["1"] = "C#",
["2"] = "D",
["3"] = "D#",
["4"] = "E",
["5"] = "F",
["6"] = "F#",
["7"] = "G",
["8"] = "G#",
["9"] = "A",
["10"] = "A#",
["11"] = "B"
},


flats_table = {
[0] = "C",
[1] = "Db",
[2] = "D",
[3] = "Eb",
[4] = "E",
[5] = "F",
[6] = "Gb",
[7] = "G",
[8] = "Ab",
[9] = "A",
[10] = "Bb",
[11] = "B"
},


flats_back_table = {
["C"] = 0,
["Db"] = 1,
["D"] = 2,
['Eb'] = 3,
["E"] = 4,
["F"] = 5,
["Gb"] = 6,
[7] = "G",
[8] = "Ab",
[9] = "A",
[10] = "Bb",
[11] = "B"
},


reverse_root_table = {
[0] = "1",
[1] = "b2",
[2] = "2",
[3] = "b3", 
[4] = "3",
[5] = "4",
[6] = "b5", 
[7] = "5", 
[8] = "b6", 
[9]= "6",
[10] = "b7", 
[11] = "7"
},

biabreverse_root_table = {
[0] = "1b",
[1] = "1#",
[2] = "1",
[3] = "b2",
[4] = "#2",
[5] = "2",
[6] = "b3",
[7] = "#3",
[8] = "3",
[9] = "b4",
[10] = "#4",
[11] = "4",
[12] = "b5",
[13] = "#5",
[14] = "5",
[15] = "b6",
[16] = "#6",
[17] = "6",
[18] = "b7",
[19] = "#7",
[20] = "7"
},


root_table = {
["b1"] = -1, 
["1"] = 0, 
["#1"] = 1, 
["b2"] = 1, 
["2"] = 2, 
["#2"] = 3, 
["b3"] = 3, 
["3"] = 4,
["#3"] = 5, 
["b4"] = 4,
["4"] = 5,
["#4"] = 6, 
["b5"] = 6, 
["5"] = 7, 
["#5"] = -4, 
["b6"] = -4, 
["6"] = -3, 
["#6"] = -2, 
["b7"] = -2, 
["7"] = -1,
["#7"] = 0
},

cccroot_table = {
["b1"] = -1, 
["1"] = 0, 
["#1"] = 1, 
["b2"] = 1, 
["2"] = 2, 
["#2"] = 3, 
["b3"] = 3, 
["3"] = 4,
["#3"] = 5, 
["b4"] = 4,
["4"] = 5,
["#4"] = 6, 
["b5"] = 6, 
["5"] = 7, 
["#5"] = -4, 
["b6"] = -4, 
["6"] = -3, 
["#6"] = -2, 
["b7"] = -2, 
["7"] = -1,
["#7"] = 0,
["<b1"] = -1, 
["<1"] = 0, 
["<#1"] = 1, 
["<b2"] = 1, 
["<2"] = 2, 
["<#2"] = 3, 
["<b3"] = 3, 
["<3"] = 4,
["<#3"] = 5, 
["<b4"] = 4,
["<4"] = 5,
["<#4"] = 6, 
["<b5"] = 6, 
["<5"] = 7, 
["<#5"] = -4, 
["<b6"] = -4, 
["<6"] = -3, 
["#6"] = -2, 
["b7"] = -2, 
["7"] = -1,
["<#7"] = 0,
["<<b1"] = -1, 
["<<1"] = 0, 
["<<#1"] = 1, 
["<<b2"] = 1, 
["<<2"] = 2, 
["<<#2"] = 3, 
["<<b3"] = 3, 
["<<3"] = 4,
["<<#3"] = 5, 
["<<b4"] = 4,
["<<4"] = 5,
["<<#4"] = 6, 
["<<b5"] = 6, 
["<<5"] = 7, 
["<<#5"] = -4, 
["<<b6"] = -4, 
["<<6"] = -3, 
["<<#6"] = -2, 
["<<b7"] = -2, 
["<<7"] = -1,
["<<#7"] = 0
},



root_colors = { 
["b1"] = {255, 0, 208},
["1"] = {255, 0, 0},
["#1"] = {132, 37, 0},
["b2"] = {132, 37, 0},
["2"] = {255, 164, 0}, 
["#2"] = {148, 89, 0}, 
["b3"] = {148, 89, 0}, 
["3"] = {255, 228, 0}, 
["#3"] = {36, 255, 0},
["b4"] = {255, 228, 0}, 
["4"] = {0, 255, 0}, 
["#4"] = {0, 98, 109}, 
["b5"] = {0, 98, 109}, 
["5"] = {100, 145, 255}, 
["#5"] = {85, 20, 181}, 
["b6"] = {85, 20, 181}, 
["6"] = {184, 10, 255}, 
["#6"] = {128, 0, 109}, 
["b7"] = {128, 0, 109}, 
["7"] =  {255, 0, 208},
["#7"] = {255, 0, 0}
},


from_onemotion_translation = {
['6'] = '6',
['7'] = '7',
['7sus2'] = 'sus27',
['9'] = '9',
['aug'] = 'aug',
['aug6'] = 'aug7',
['dim'] = 'dim',
['dim7'] = 'dim7',
['m13'] = '-13',
['m7b5'] = '%7',
['m9'] = '-9',
['maj7'] = 'maj7',
['maj7#5'] = '+maj7',
['maj7sus2'] = 'sus2maj7',
['mb6'] = '-b6',
['sus2'] = 'sus2',
['sus24'] = 'sus24',
["13"] = '13',
["5"] = '5',
["6"] = '6',
["7b9"] = 'b9',
["7no3"] = '57',
["7sus24"] = 'sus247',
["7sus4"] = 'sus7',
["add2"] = 'add2',
["add4"] = 'add4',
["add9"] = '9',
["madd9"] = '-9',
["m"] = '-',
["m6"] = '-6',
["m7"] = '-7',
["madd2"] = '-add2',
["madd4"] = '-add4',
["maj7no3"] = '5maj7',
["maj7sus24"] = 'sus24maj7',
["maj7sus4"] = 'sus4maj7',
["mmaj7"] = '-maj7',
["sus2"] = '59',
["sus4"] = 'sus',
["susb2"] = '5b9',
['aug6'] = '+7'
},

to_onemotion_translation = {
['z'] = "", 
['u'] = "", 
['sus2'] = 'sus2', 
['sus27'] = '7sus2', 
['sus2maj7'] = 'maj7sus2', 
['sus2j7'] = 'maj7sus2', 
['sus24'] = 'sus24', 
['sus247'] = "7sus24", 
['sus24maj7'] = "maj7sus24", 
['sus24j7'] = "maj7sus24", 
['6'] = "6", 
['m'] = "m", 
['madd2'] = "madd2", 
['madd4'] = "madd4", 
['m6'] = "m6",
['mb6'] = 'mb6',
['m7'] = "m7",
['mmaj7'] = "mmaj7",
['mj7'] = "mmaj7",
['m9'] =  'm9', 
['m11'] = "madd4", 
['m13'] = 'm13', 
['-'] = "m", 
['-add2'] = "madd2", 
['-add4'] = "madd4", 
['-6'] = "m6",
['-b6'] = 'mb6',
['-7'] = "m7",
['-maj7'] = "mmaj7",
['-j7'] = "mmaj7",
['-9'] =  'm9', 
['-11'] = "madd4",  
['-13'] = 'm13', 
['add2'] = "add2", 
['add4'] = "add4", 
['6'] = '6', 
['7'] = '7', 
['maj7'] = 'maj7', 
['j7'] = 'maj7', 
['9'] = '9', 
['b9'] = "7b9",
['11'] = "add4", 
['13'] = "13",
['sus'] = "sus4",
['sus7'] = "7sus4",
['susmaj7'] = "maj7sus4",
['susj7'] = "maj7sus4",
['sus4'] =  "sus4",
['sus47'] =  "7sus4",
['sus4maj7'] = "maj7sus4",
['sus4j7']= "maj7sus4",
['dim'] = 'dim', 
['dim7'] = 'dim7', 
['hdim7'] = 'm7b5', 
['o'] = 'dim', 
['o7'] = 'm7b5',
['%'] =  'm7b5', 
['%7'] =  'm7b5', 
['5'] = "5", 
['57'] = "7no3",
['5maj7'] = "maj7no3",
['5j7'] = "maj7no3",
['59'] = "sus2",
['5b9'] = "susb2",
['aug'] = 'aug', 
['aug7'] = 'aug6', 
['augmaj7'] = 'maj7#5', 
['augj7'] = 'maj7#5', 
['+'] = 'aug',
['+7'] ='aug6', 
['+maj7'] = 'maj7#5', 
['+j7'] = 'maj7#5'
},

worries = {
"add",
"maj",
"aug",
"b"
},

to_biab_translation = {
['u'] = "", 
['sus2'] = '9', 
['sus27'] = '9', 
['sus2maj7'] = 'Maj9', 
['sus2j7'] = 'Maj9', 
['sus24'] = '9sus', 
['sus247'] = "9sus",  
['6'] = "6", 
['m'] = "m", 
['madd2'] = "madd2", 
['madd4'] = "madd4", 
['m6'] = "m6",
['mb6'] = 'm#5',
['m7'] = "m7",
['mmaj7'] = "mMaj7",
['mj7'] = "mMaj7",
['m9'] =  'm9', 
['m11'] = "m11", 
['m13'] = 'm13', 
['-'] = "m", 
['-add2'] = "madd2", 
['-add4'] = "madd4", 
['-6'] = "m6",
['-b6'] = 'm#5',
['-7'] = "m7",
['-maj7'] = "mMaj7",
['-j7'] = "mMaj7",
['-9'] =  'm9', 
['-11'] = "m11",  
['-13'] = 'm13', 
['add2'] = "add2", 
['add4'] = "sus", 
['6'] = '6', 
['7'] = '7', 
['maj7'] = 'Maj7', 
['j7'] = 'Maj7', 
['9'] = '9', 
['#9'] = "7#9",
['11'] = "add4", 
['13'] = "13",
['sus'] = "sus",
['sus7'] = "7sus",
['sus4'] =  "sus",
['sus47'] =  "7sus",
['dim'] = 'dim', 
['dim7'] = 'dim7', 
['hdim7'] = 'm7b5', 
['o'] = 'dim',  
['o7'] = 'm7b5',
['%'] =  'm7b5', 
['%7'] =  'm7b5', 
['5'] = "5", 
['57'] = "5",
['5maj7'] = "5",
['5j7'] = "5",
['59'] = "5",
['5b9'] = "5",
['aug'] = 'aug', 
['aug7'] = 'aug', 
['augmaj7'] = 'aug', 
['augj7'] = 'aug', 
['+'] = 'aug',
['+7'] ='aug', 
['+maj7'] = 'aug', 
['+j7'] = 'aug'
},


to_ccc_translation = {
['u'] = "", 
['sus2'] = 'sus2', 
['sus27'] = '7sus2', 
['sus2maj7'] = 'Maj7sus2', 
['sus2j7'] = 'Maj7sus2', 
['sus24'] = 'sus2', 
['sus247'] = "7sus2",  
['6'] = "6", 
['m'] = "m", 
['madd2'] = "-add2", 
['madd4'] = "-add4", 
['m6'] = "m6",
['mb6'] = 'mb6',
['m7'] = "m7",
['mmaj7'] = "mMaj7",
['mj7'] = "mj7",
['m9'] =  'm9', 
['m11'] = "m11", 
['m13'] = 'm13', 
['-'] = "m", 
['-add2'] = "-add2", 
['-add4'] = "-add4", 
['-6'] = "-6",
['-b6'] = '-b6',
['-7'] = "-7",
['-maj7'] = "-Maj7",
['-j7'] = "-j7",
['-9'] =  '-9', 
['-11'] = "-11",  
['-13'] = '-13', 
['add2'] = "add2", 
['add4'] = "add4", 
['6'] = '6', 
['7'] = '7', 
['maj7'] = 'Maj7', 
['j7'] = 'j7', 
['9'] = '9', 
['#9'] = "7#9",
['11'] = "4", 
['13'] = "13",
['sus'] = "sus",
['sus7'] = "7sus",
['sus4'] =  "sus4",
['sus47'] =  "7sus4",
['dim'] = 'dim', 
['dim7'] = 'dim7', 
['hdim7'] = 'm7b5', 
['o'] = 'dim',  
['o7'] = 'm7b5',
['%'] =  'm7b5', 
['%7'] =  'm7b5', 
['5'] = "5", 
['57'] = "75",
['5maj7'] = "Maj75",
['5j7'] = "j5",
['59'] = "5",
['5b9'] = "5",
['aug'] = '+', 
['aug7'] = '7+', 
['augmaj7'] = 'Maj7+', 
['augj7'] = 'j7+', 
['+'] = '+',
['+7'] ='7+', 
['+maj7'] = 'Maj7+', 
['+j7'] = 'j7+'
},


major_trend_table = {
[1] = {"1",18,{{'5',22},{'4',16},{'6m',9},{'2m',5},{'3m',4}},"1"},
[2] = {"4",14,{{'1',33},{'5',24},{'6m',7},{'2m',4},{'3m',4},{'4m',2}},"4"},
[3] = {"5",14,{{'1',32},{'4',17},{'6m',15},{'2m',4},{'3m',3}},"5"},
[4] = {"6m",8,{{'4',24},{'5',23},{'1',11},{'2m',6},{'3m',6}},"6"},
[5] = {"2m",7,{{'5',29},{'1',18},{'4',14},{'6m',10},{'3m',9}},"2"},
[6] = {"3m",4,{{'4',33},{'6m',16},{'2m',13},{'1',8},{'5',8}},"3"},
[7] = {"2",2,{{'5',30},{'4',22},{'1',10},{'3m',5},{'6m',4},{'2m',3},{'b3',3},{'3',3}},"2"},
[8] = {"3",2,{{'6m',45},{'4',27},{'1',8},{'5',3}},"3"},
[9] = {"b6",1,{{'b7',34},{'1',23},{'5',16},{'b3',6},{'4',6},{'4m',4},{'6',4},{'6m',3},{'b2',2}},"b6"},
[10] = {"6",1,{{'2m',38},{'4',14},{'2',11},{'1',10},{'5',7},{'b7',4},{'6m',3},{'3',2},{'b6',2},{'7',2}},"6"},
[11] = {"b7",1,{{'1',27},{'4',27},{'5',9},{'6m',7},{'b3',4},{'b6',4},{'2m',3}},"b7"},
[12] = {"7°",1,{{'1',50},{'6m',23},{'5',9},{'3m',5},{'4',5},{'b7',4},{'2m',3}},"7"},
},

chains_table = {
[1] = {"Most POPular!"," 1   5   6m   4 ", {{1,"1","1"},{2,"5","5"},{3,"6m","6"},{4,"4","4"}}},
[2] = {"Most popular dark start"," 6m   4   1   5 ",{{1,"6m","6"},{2,"4","4"},{3,"1","1"},{4,"5","5"}}},
[3] = {"I will always love you"," 1   6m   4   5 ",{{1,"1","1"},{2,"6m","6"},{3,"4","4"},{4,"5","5"}}},
[4] = {"Old Mexico", " 1   1   1   57   57   57   57   1 ",{{1,"1","1"},{2,"1","1"},{3,"1","1"},{4,"57","5"},{5,"57","5"},{6,"57","5"},{7,"57","5"},{8,"1","1"}}},
[5] = {"No one for a while"," 6m   5   4   5 ",{{1,"6m","6"},{2,"5","5"},{3,"4","4"},{4,"5","5"}}},
[6] = {"More than a feeling"," 1   4   6m   5 ",{{1,"1","1"},{2,"4","4"},{3,"6m","6"},{4,"5","5"}}},
[7] = {"Pachabel", " 1   5   6m   3m   4   1   4   5 ",{{1,"1","1"},{2,"5","5"},{3,"6m","6"},{4,"3m","3"},{5,"4","4"},{6,"1","1"},{7,"4","4"},{8,"5","5"}}},
[8] = {"I believe I can fly"," 1   6m7   2m7   5 ",{{1,"1","1"},{2,"4","4"},{3,"6m","6"},{4,"5","5"}}},
[9] = {"Island Chill"," 2m    1    1    2m ",{{1,"2m","2"},{2,"1","1"},{3,"1","1"},{4,"2m","2"}}},
[10] = {"Down, down, down"," 1   1/7   6m  6m/5   4   4/3   2m   5 ",{{1,"1","1"},{2,"1/7","1"},{3,"6m","6"},{4,"6m/5","6"},{5,"4","4"},{6,"4/3","4"},{7,"2m","2"},{8,"5","5"}}},
[11] = {"Sweet home Alabama"," 1   b7   4    4 ",{{1,"1","1"},{2,"b7","b7"},{3,"4","4"},{4,"4","4"}}}
},


button_table = {
[1] = {"L","            Major Chords",{}},
[2] = {'9','9      ',{[5]=1}}, 
[3] = {'maj7','maj7   ',{[1]=1,[4]=1}}, 
[4] = {'7','7      ',{[5]=1}}, 
[5] = {'6','6      ',{[1]=1,[4]=1,[5]=1}}, 
[6] = {'add2','add2   ',{[1]=1,[2]=1,[5]=1}}, 
[7] = {'',"       ",{[1]=1,[4]=1,[5]=1}},
[8] = {"L","            Minor Chords",{}},
[9] = {'mmaj7','mmaj7  ',{}}, 
[10] = {'m7','m7     ',{[2]=1,[3]=1,[6]=1}}, 
[11] = {'m6','m6     ',{[2]=1}},
[12] = {'mb6','mb6    ',{[3]=1,[6]=1}},
[13] = {'madd2','madd2  ',{[2]=1,[6]=1}},
[14] = {'m','m      ',{[2]=1,[3]=1,[6]=1}},
[15] = {"L","            Suspended Chords",{}},
[16] = {'sus','sus    ',{[2]=1,[3]=1,[3]=1,[5]=1,[6]=1}}, 
[17] = {'sus24','sus24  ',{[1]=1,[2]=1,[5]=1,[6]=1}}, 
[18] = {'sus2','sus2   ',{[1]=1,[2]=1,[4]=1,[5]=1,[6]=1}},
[19] = {"L","            Augmented Chords and Diminished Chords"},
[20] = {'+', '+      ',{}},
[22] = {'%7','%7     ',{[7]=1}},
[23] = {'dim7','dim7   ',{}},
[24] = {'dim','dim    ',{[7]=1}},
[25] = {"L","            Power Chords and Unison"},
[26] = {'5','5      ',{[1]=1,[2]=1,[3]=1,[4]=1,[5]=1,[6]=1}}, 
[27] = {'u','u      ',{[1]=1,[2]=1,[3]=1,[4]=1,[5]=1,[6]=1,[7]=1}}
},


conflict_table ={ 
['addb2'] = "@þþ¬2",  
['add'] = "@þþ", 
['maj'] = "m@j",
['mb6'] = "m¬6", 
['-b6'] = "-¬6", 
['dim'] = "þim", 
["aug"] = "@ug"
},

reverse_conflict_table ={ 
['@þþ¬2'] = "addb2",  
['@þþ'] = "add", 
['m@j'] = "maj",
['m¬6'] = "mb6", 
['-¬6'] = "-b6", 
['þim'] = "dim", 
["@ug"] = "aug"
},

type_table ={
['-'] = {0,3,7},
['-11'] = {0,3,7,10,14,17},
['-13'] = {0,3,7,10,14,17,21},
['-6'] = {0,3,7,9},
['-7'] = {0,3,7,10},
['-9'] = {0,3,7,10,14},
['-add2'] = {0,2,3,7},
['-add4'] = {0,3,5,7},
['-addb2'] = {0,1,3,7},
['-b6'] = {0,3,7,8},
['-j7'] = {0,3,7,11},
['-maj7'] = {0,3,7,11},
['%'] = {0,3,6,10},
['%7'] = {0,3,6,10},
['+'] = {0,4,8},
['+7'] = {0,4,8,10},
['+j7'] = {0,4,8,11},
['+maj7'] = {0,4,8,11},
['11'] = {0,4,7,10,14,17},
['13'] = {0,4,7,10,14,17,21},
['5'] = {0,7},
['57'] = {0,7,10},
['59'] = {0,7,10,14},
['5b9'] = {0,7,10,13},
['5j7'] = {0,7,11},
['5maj7'] = {0,7,11},
['6'] = {0,4,7,9},
['7'] = {0,4,7,10},
['7+'] = {0,4,8,10},
['7aug7'] = {0,4,8,10},
['7sus'] = {0,5,7,10},
['7sus2'] = {0,2,7,10},
['7sus24'] = {0,2,5,10},
['7sus4'] = {0,5,7,10},
['9'] = {0,4,7,10,14},
['add2'] = {0,2,4,7},
['add4'] = {0,4,5,7},
['aug'] = {0,4,8},
['aug7'] = {0,4,8,10},
['augj7'] = {0,4,8,11},
['augmaj7'] = {0,4,8,11},
['b6'] = {0,4,7,8},
['b9'] = {0,4,7,10,13},
['dim'] = {0,3,6},
['dim7'] = {0,3,6,9},
['hdim7'] = {0,3,6,10},
['j7'] = {0,4,7,11},
['j7+'] = {0,4,8,11},
['j7aug'] = {0,4,8,11},
['j7sus'] = {0,5,7,11},
['j7sus2'] = {0,2,7,11},
['j7sus24'] = {0,2,5,11},
['j7sus4'] = {0,5,7,11},
['m'] = {0,3,7},
['m11'] = {0,3,7,10,14,17},
['m13'] = {0,3,7,10,14,17,21},
['m6'] = {0,3,7,9},
['m7'] = {0,3,7,10},
['m9'] = {0,3,7,10,14},
['madd2'] = {0,2,3,7},
['madd4'] = {0,3,5,7},
['maddb2'] = {0,1,3,7},
['maj7'] = {0,4,7,11},
['maj7+'] = {0,4,8,11},
['maj7aug'] = {0,4,8,11},
['maj7sus'] = {0,5,7,11},
['maj7sus2'] = {0,2,7,11},
['maj7sus24'] = {0,2,5,11},
['maj7sus4'] = {0,5,7,11},
['mb6'] = {0,3,7,8},
['mj7'] = {0,3,7,11},
['mmaj7'] = {0,3,7,11},
['o'] = {0,3,6},
['o7'] = {0,3,6,9},
['sus'] = {0,5,7},
['sus2'] = {0,2,7},
['sus24'] = {0,2,5},
['sus247'] = {0,2,5,10},
['sus24j7'] = {0,2,5,11},
['sus24maj7'] = {0,2,5,11},
['sus27'] = {0,2,7,10},
['sus2j7'] = {0,2,7,11},
['sus2maj7'] = {0,2,7,11},
['sus4'] = {0,5,7},
['sus47'] = {0,5,7,10},
['sus4j7'] = {0,5,7,11},
['sus4maj7'] = {0,5,7,11},
['sus7'] = {0,5,7,10},
['susj7'] = {0,5,7,11},
['susmaj7'] = {0,5,7,11},
['u'] = {36},
['z'] = {0,4,7}
},

type_table_old ={
['z'] = {0,4,7}, 
['u'] = {36}, 
['sus2'] = {0,2,7}, 
['sus27'] = {0,2,7,10}, 
['sus2maj7'] = {0,2,7,11}, 
['sus2j7'] = {0,2,7,11}, 
['sus24'] = {0,2,5}, 
['sus247'] = {0,2,5,10}, 
['sus24maj7'] = {0,2,5,11}, 
['sus24j7'] = {0,2,5,11},
['6'] = {0,4,7,9}, 
['m'] = {0,3,7},
['maddb2'] = {0,1,3,7}, 
['madd2'] = {0,2,3,7}, 
['madd4'] = {0,3,5,7}, 
['m6'] = {0,3,7,9},
['mb6'] = {0,3,7,8},
['m7'] = {0,3,7,10}, 
['mmaj7'] = {0,3,7,11}, 
['mj7'] = {0,3,7,11}, 
['m9'] = {0,3,7,10,14}, 
['m11'] = {0,3,7,10,14,17}, 
['m13'] = {0,3,7,10,14,17,21}, 
['-'] = {0,3,7},
['-addb2'] = {0,1,3,7}, 
['-add2'] = {0,2,3,7}, 
['-add4'] = {0,3,5,7}, 
['-6'] = {0,3,7,9},
['-b6'] = {0,3,7,8},
['-7'] = {0,3,7,10}, 
['-maj7'] = {0,3,7,11}, 
['-j7'] = {0,3,7,11}, 
['-9'] = {0,3,7,10,14}, 
['-11'] = {0,3,7,10,14,17}, 
['-13'] = {0,3,7,10,14,17,21}, 
['add2'] = {0,2,4,7}, 
['add4'] = {0,4,5,7}, 
['6'] = {0,4,7,9}, 
['7'] = {0,4,7,10}, 
['maj7'] = {0,4,7,11}, 
['j7'] = {0,4,7,11}, 
['9'] = {0,4,7,10,14}, 
['b9'] = {0,4,7,10,13}, 
['#9'] = {0,4,7,10,15}, 
['11'] = {0,4,7,10,14,17}, 
['13'] = {0,4,7,10,14,17,21}, 
['sus'] = {0,5,7}, 
['sus7'] = {0,5,7,10}, 
['susmaj7'] = {0,5,7,11}, 
['susj7'] = {0,5,7,11}, 
['sus4'] = {0,5,7}, 
['sus47'] = {0,5,7,10}, 
['sus4maj7'] = {0,5,7,11}, 
['sus4j7'] = {0,5,7,11}, 
['dim'] = {0,3,6}, 
['dim7'] = {0,3,6,9}, 
['hdim7'] = {0,3,6,10}, 
['o'] = {0,3,6}, 
['o7'] = {0,3,6,9}, 
['%'] = {0,3,6,10}, 
['%7'] = {0,3,6,10}, 
['5'] = {0,7}, 
['57'] = {0,7,10}, 
['5maj7'] = {0,7,11}, 
['5j7'] = {0,7,11}, 
['59'] = {0,7,10,14}, 
['5b9'] = {0,7,10,13}, 
['aug'] = {0,4,8}, 
['aug7'] = {0,4,8,10}, 
['augmaj7'] = {0,4,8,11}, 
['augj7'] = {0,4,8,11}, 
['+'] = {0,4,8}, 
['+7'] = {0,4,8,10}, 
['+maj7'] = {0,4,8,11}, 
['+j7'] = {0,4,8,11}
}
}

return musictheory
