-- @description numbers2notes_config
-- @version 1.7.2
-- @noindex
-- @author Rock Kennedy
-- @about
--   Configuration file for Numbers2Notes.
--   Contains Plugin Source URLs and the Master Track Layout.
-- @changelog
--   + Links Updated

local config = {}

-- 1. PLUGIN SOURCES (Instructions/Links)
config.pluginsources = {
    [1] = "Included with Reaper (Cockos/Stillwell). No additional download needed.",
    [2] = "ReaPack: 'ReaTeam Scripts' repository.",
    [3] = "Included N2N JSFX (Should be installed with this script).",
    [4] = "ReaPack: 'Geraint's JSFX' repository. URL: https://github.com/geraintluff/jsfx-pad-synth",
    [5] = "ReaPack: 'Saike Tools' repository. URL: https://raw.githubusercontent.com/JoepVanlier/JSFX/master/index.xml",
    [6] = "Reapack: 'StevieKeys JSFX'. URL: https://raw.githubusercontent.com/Steviekeys/StevieKeys_JSFX2/master/index.xml",
    [7] = "ReaPack: 'Tukan Studios' repository. URL: https://raw.githubusercontent.com/TukanStudios/TUKAN_STUDIOS_PLUGINS/main/index2.xml",
    [8] = "Surge XT (Free Synth): https://surge-synthesizer.github.io/",
    [9] = "Airwindows (Calibre, Isolator, Holt, Tube, Drive): https://www.airwindows.com/",
    [10] = "Pro Punk Drums: https://www.propunkstudio.com/product/pro-punk-drums/",
    [11] = "STFU (Volume Shaper): https://zeeks.app/",
    [12] = "Keyzone Classic: https://plugins4free.com/plugin/2848/",
    [13] = "Drum8: https://audiolatry.gumroad.com/l/drum8",
    [14] = "Drum8: https://audiolatry.gumroad.com/l/drumtastic",
    [15] = "MT Power Drumkit2: https://www.powerdrumkit.com/download76187.php",
    [16] = "Vital: https://vital.audio/#getvital",[17] = "Chmaha's Airwindows Ports: https://github.com/chmaha/airwindows-JSFX-ports/raw/main/index.xml",
    [18] = "Sixth Sample Deelay: https://sixthsample.com/deelay/",
    [19] = "OMG Instruments BlueARP: https://omg-instruments.com/wp/?page_id=46",
	[20] = "Librearp: https://librearp.gitlab.io/download/",
	[99] = "Unknown Source."
}

config.vsti_drum_options = {
    { selection_label = "Monster Drums", search = "VSTi: MONSTER Drums v3", preset = "N2N_Start", pluginsources = 10 },
    { selection_label = "Pro Punk Drums", search = "VST3i: Pro Punk Drums", preset = "Pro Punk Drums", pluginsources = 10 },
    { selection_label = "Drum8", search = "Drum8", preset = "Drum8", pluginsources = 13 },
    { selection_label = "Drumtastic", search = "Drumtastic", preset = "Drumtastic", pluginsources = 14 },
    { selection_label = "MT Power Drum Kit 2", search = "MT Power Drum Kit 2", preset = "MT Power Drum Kit 2", pluginsources = 15 },
    { selection_label = "Select Other...", search = "", preset = "", pluginsources = 0 }
}


config.drum_preset_options = {
  { selection_label = "One Based MIDI", preset = "One Based MIDI" },
  { selection_label = "Pro Punk Drums", preset = "Pro Punk Drums" },
  { selection_label = "Read_Me_For_Kit_Info", preset = "Read_Me_For_Kit_Info" },
  { selection_label = "Roland SRX", preset = "Roland SRX" },
  { selection_label = "Spitfire-LABS", preset = "Spitfire-LABS" },
  { selection_label = "SSD5 Frees", preset = "SSD5 Frees" },
  { selection_label = "Zero Based MIDI", preset = "Zero Based MIDI" },
  { selection_label = "[8-BIT] 01 Game Over", preset = "[8-BIT] 01 Game Over" },
  { selection_label = "[8-BIT] 02 Krusty Kit", preset = "[8-BIT] 02 Krusty Kit" },
  { selection_label = "[BEATBOX] 01 Street Jam", preset = "[BEATBOX] 01 Street Jam" },
  { selection_label = "[BEATBOX] 02 Humana Hit", preset = "[BEATBOX] 02 Humana Hit" },
  { selection_label = "[BEATBOX] 03 Disco Bee", preset = "[BEATBOX] 03 Disco Bee" },
  { selection_label = "[BEATBOX] 04 Big Badda Boom", preset = "[BEATBOX] 04 Big Badda Boom" },
  { selection_label = "[CINE] 01 Hellboy Cube", preset = "[CINE] 01 Hellboy Cube" },
  { selection_label = "[CINE] 02 CineFlix Perc", preset = "[CINE] 02 CineFlix Perc" },
  { selection_label = "[CINE] 03 Doomsday 2040", preset = "[CINE] 03 Doomsday 2040" },
  { selection_label = "[DDUT] 01 Vian Dangdut Kit", preset = "[DDUT] 01 Vian Dangdut Kit" },
  { selection_label = "[DDUT] 02 Paralon Yona", preset = "[DDUT] 02 Paralon Yona" },
  { selection_label = "[DDUT] 03 Yonk Graffity", preset = "[DDUT] 03 Yonk Graffity" },
  { selection_label = "[DISCO] 01 Discoria", preset = "[DISCO] 01 Discoria" },
  { selection_label = "[DISCO] 02 Dance Club", preset = "[DISCO] 02 Dance Club" },
  { selection_label = "[DRUM MC] 01 Roland R8", preset = "[DRUM MC] 01 Roland R8" },
  { selection_label = "[DRUM MC] 02 Korg DDD-1", preset = "[DRUM MC] 02 Korg DDD-1" },
  { selection_label = "[DRUM MC] 03 Casio VL-1", preset = "[DRUM MC] 03 Casio VL-1" },
  { selection_label = "[DRUM MC] 04 Roland TR-606", preset = "[DRUM MC] 04 Roland TR-606" },
  { selection_label = "[DRUM MC] 05 Roland TR-626", preset = "[DRUM MC] 05 Roland TR-626" },
  { selection_label = "[DRUM MC] 06 Roland TR-707", preset = "[DRUM MC] 06 Roland TR-707" },
  { selection_label = "[DRUM MC] 07 Roland TR-727", preset = "[DRUM MC] 07 Roland TR-727" },
  { selection_label = "[DRUM MC] 08 Roland TR-808", preset = "[DRUM MC] 08 Roland TR-808" },
  { selection_label = "[DRUM MC] 09 Roland TR-909", preset = "[DRUM MC] 09 Roland TR-909" },
  { selection_label = "[DRUM MC] 10 Clavia Nord Drum", preset = "[DRUM MC] 10 Clavia Nord Drum" },
  { selection_label = "[DRUM MC] 11 Linn LinnDrum", preset = "[DRUM MC] 11 Linn LinnDrum" },
  { selection_label = "[DRUM MC] 12 Linn Linn9000", preset = "[DRUM MC] 12 Linn Linn9000" },
  { selection_label = "[DRUM MC] 13 Alesis HR16", preset = "[DRUM MC] 13 Alesis HR16" },
  { selection_label = "[DRUM MC] 14 E-mu Drumulator", preset = "[DRUM MC] 14 E-mu Drumulator" },
  { selection_label = "[DRUM MC] 15 Yamaha RX5", preset = "[DRUM MC] 15 Yamaha RX5" },
  { selection_label = "[DRUM MC] 16 Korg KR-55", preset = "[DRUM MC] 16 Korg KR-55" },
  { selection_label = "[DRUM MC] 17 Oberheim DMX", preset = "[DRUM MC] 17 Oberheim DMX" },
  { selection_label = "[DRUM MC] 18 Linn LM-1", preset = "[DRUM MC] 18 Linn LM-1" },
  { selection_label = "[DRUM MC] 19 Boss DR-110", preset = "[DRUM MC] 19 Boss DR-110" },
  { selection_label = "[DRUM MC] 20 SCI DrumTrax", preset = "[DRUM MC] 20 SCI DrumTrax" },
  { selection_label = "[ELECTRO] 01 Futura Kit", preset = "[ELECTRO] 01 Futura Kit" },
  { selection_label = "[ELECTRO] 02 ElectroGroove", preset = "[ELECTRO] 02 ElectroGroove" },
  { selection_label = "[ELECTRO] 03 Dream Catcher", preset = "[ELECTRO] 03 Dream Catcher" },
  { selection_label = "[ELECTRO] 04 Techa Kit", preset = "[ELECTRO] 04 Techa Kit" },
  { selection_label = "[ELECTRO] 05 Matrix Kit", preset = "[ELECTRO] 05 Matrix Kit" },
  { selection_label = "[ELECTRO] 06 Trappa Kit", preset = "[ELECTRO] 06 Trappa Kit" },
  { selection_label = "[FUNK] 01 Funk It", preset = "[FUNK] 01 Funk It" },
  { selection_label = "[FUNK] 02 SoulVibe", preset = "[FUNK] 02 SoulVibe" },
  { selection_label = "[FUNK] 03 FonkaWonka", preset = "[FUNK] 03 FonkaWonka" },
  { selection_label = "[FUNK] 04 Funky Flix", preset = "[FUNK] 04 Funky Flix" },
  { selection_label = "[HIP HOP] 01 CocaCola Kit", preset = "[HIP HOP] 01 CocaCola Kit" },
  { selection_label = "[HIP HOP] 02 Drop It, Hop It", preset = "[HIP HOP] 02 Drop It, Hop It" },
  { selection_label = "[HIP HOP] 03 Groove Ghetto", preset = "[HIP HOP] 03 Groove Ghetto" },
  { selection_label = "[INDUST] 01 Factory Reset", preset = "[INDUST] 01 Factory Reset" },
  { selection_label = "[INDUST] 02 Barrel Beater", preset = "[INDUST] 02 Barrel Beater" },
  { selection_label = "[JAZZ] 01 Tooth Brush Kit", preset = "[JAZZ] 01 Tooth Brush Kit" },
  { selection_label = "[JAZZ] 02 Jive Kit", preset = "[JAZZ] 02 Jive Kit" },
  { selection_label = "[JAZZ] 03 Jazz For You", preset = "[JAZZ] 03 Jazz For You" },
  { selection_label = "[LOFI] 01 Summer Picnic", preset = "[LOFI] 01 Summer Picnic" },
  { selection_label = "[METAL] 01 RacikSuara Metal", preset = "[METAL] 01 RacikSuara Metal" },
  { selection_label = "[METAL] 02 Kalkal Tremor", preset = "[METAL] 02 Kalkal Tremor" },
  { selection_label = "[METAL] 03 Caveman", preset = "[METAL] 03 Caveman" },
  { selection_label = "[METAL] 04 Animus Monster", preset = "[METAL] 04 Animus Monster" },
  { selection_label = "[METAL] 05 Metal Mayhem", preset = "[METAL] 05 Metal Mayhem" },
  { selection_label = "[METAL] 06 Adun SG Djent Kit", preset = "[METAL] 06 Adun SG Djent Kit" },
  { selection_label = "[ORCH] 01 Marching Ants", preset = "[ORCH] 01 Marching Ants" },
  { selection_label = "[POP] 01 Acoustica Hits", preset = "[POP] 01 Acoustica Hits" },
  { selection_label = "[POP] 02 Pidux Pop Kit", preset = "[POP] 02 Pidux Pop Kit" },
  { selection_label = "[POP] 03 Pop Jam", preset = "[POP] 03 Pop Jam" },
  { selection_label = "[POP] 04 eNKa Worship Kit", preset = "[POP] 04 eNKa Worship Kit" },
  { selection_label = "[POP] 05 YPB Cajon Kit", preset = "[POP] 05 YPB Cajon Kit" },
  { selection_label = "[POP] 06 Red Drums", preset = "[POP] 06 Red Drums" },
  { selection_label = "[POP] 07 Pepadu Kit", preset = "[POP] 07 Pepadu Kit" },
  { selection_label = "[POP] 08 Steven's LAS Kit", preset = "[POP] 08 Steven's LAS Kit" },
  { selection_label = "[POP] 09 K Drum", preset = "[POP] 09 K Drum" },
  { selection_label = "[POP] 10 Teffy's Kit", preset = "[POP] 10 Teffy's Kit" },
  { selection_label = "[POP] 11 Emerald Kit", preset = "[POP] 11 Emerald Kit" },
  { selection_label = "[PUNK] 01 Punkadelic Kit", preset = "[PUNK] 01 Punkadelic Kit" },
  { selection_label = "[PUNK] 02 Altanative Kit", preset = "[PUNK] 02 Altanative Kit" },
  { selection_label = "[REGGAE] 01 Adun SG Reggae Kit", preset = "[REGGAE] 01 Adun SG Reggae Kit" },
  { selection_label = "[REGGAE] 02 Reggae Cezzo Kit", preset = "[REGGAE] 02 Reggae Cezzo Kit" },
  { selection_label = "[REGGAE] 03 Zion Reggae", preset = "[REGGAE] 03 Zion Reggae" },
  { selection_label = "[RNB] 01 Groove Nation", preset = "[RNB] 01 Groove Nation" },
  { selection_label = "[RNB] 02 Soul N Joy", preset = "[RNB] 02 Soul N Joy" },
  { selection_label = "[ROCK] 01 Sonic Rock", preset = "[ROCK] 01 Sonic Rock" },
  { selection_label = "[ROCK] 02 Dragon Yao Gun", preset = "[ROCK] 02 Dragon Yao Gun" },
  { selection_label = "[ROCK] 03 Water Jug Kit", preset = "[ROCK] 03 Water Jug Kit" },
  { selection_label = "[ROCK] 04 RacikSuara V-Rock", preset = "[ROCK] 04 RacikSuara V-Rock" },
  { selection_label = "[ROCK] 05 Pulse Rock", preset = "[ROCK] 05 Pulse Rock" },
  { selection_label = "[ROCK] 06 Heavy Hitter", preset = "[ROCK] 06 Heavy Hitter" },
  { selection_label = "[ROCK] 07 Boom Bang Kit", preset = "[ROCK] 07 Boom Bang Kit" },
  { selection_label = "[SYNWAV] 01 G-Linn Kit", preset = "[SYNWAV] 01 G-Linn Kit" },
  { selection_label = "[SYNWAV] 02 Groovebox Story", preset = "[SYNWAV] 02 Groovebox Story" },
  { selection_label = "[SYNWAV] 03 Midnight Glow", preset = "[SYNWAV] 03 Midnight Glow" },
  { selection_label = "Clear All", preset = "Clear All" },
  { selection_label = "Drum8", preset = "Drum8" },
  { selection_label = "Drumtastic", preset = "Drumtastic" },
  { selection_label = "EZdrummer 2 Americana", preset = "EZdrummer 2 Americana" },
  { selection_label = "Ezdrummer 2 Classic", preset = "Ezdrummer 2 Classic" },
  { selection_label = "EZDrummer Default Kit", preset = "EZDrummer Default Kit" },
  { selection_label = "EZDrummer Nashville", preset = "EZDrummer Nashville" },
  { selection_label = "EZDrummer", preset = "EZDrummer" },
  { selection_label = "EzDrummer2", preset = "EzDrummer2" },
  { selection_label = "EZDrummer2_Hip-Hop", preset = "EZDrummer2_Hip-Hop" },
  { selection_label = "Funkbass", preset = "Funkbass" },
  { selection_label = "GMajor", preset = "GMajor" },
  { selection_label = "LilKit", preset = "LilKit" },
  { selection_label = "MT-PowerDrumKit", preset = "MT-PowerDrumKit" },
  { selection_label = "MultiKit", preset = "MultiKit" },
  { selection_label = "Nashville Copy", preset = "Nashville Copy" },
  { selection_label = "Note Names", preset = "Note Names" }
}




config.vsti_synth_options = {
    { selection_label = "Surge Sustained", search = "CLAP: Surge XT", preset = "N2N_Ambient2", pluginsources = 8 },
    { selection_label = "Surge Pops", search = "CLAP: Surge XT", preset = "N2N_Delay Pops 2", pluginsources = 8 },
    { selection_label = "Surge Plucks", search = "CLAP: Surge XT", preset = "N2N_Plucks", pluginsources = 8 },
    { selection_label = "December Synth", search = "JS: December Synth", preset = "", pluginsources = 7 }, 
    { selection_label = "DecentSampler", search = "DecentSampler", preset = "", pluginsources = 7 },
    { selection_label = "Keyzone Classic", search = "Keyzone Classic", preset = "N2N Default", pluginsources = 12 },
    { selection_label = "POLY 24", search = "JS: POLY 24", preset = "", pluginsources = 7 },
    { selection_label = "Vital", search = "VST3i: Vital", preset = "", pluginsources = 16 },
    { selection_label = "WTFM Synth", search = "JS: WTFM Synth", preset = "", pluginsources = 7 },
    { selection_label = "Select Other...", search = "", preset = "", pluginsources = 0 }
}

config.vsti_bass_options = {
    { selection_label = "Surge Bass", search = "CLAP: Surge XT", preset = "N2N_Bass", pluginsources = 8 },
    { selection_label = "Surge Blips", search = "CLAP: Surge XT", preset = "N2N_Blips", pluginsources = 8 },
    { selection_label = "Surge Sustained", search = "CLAP: Surge XT", preset = "N2N_Ambient2", pluginsources = 8 },
    { selection_label = "Surge Plucks", search = "CLAP: Surge XT", preset = "N2N_Plucks", pluginsources = 8 },
    { selection_label = "December Synth", search = "JS: December Synth", preset = "", pluginsources = 7 }, 
    { selection_label = "DecentSampler", search = "DecentSampler", preset = "", pluginsources = 7 },
    { selection_label = "Keyzone Classic", search = "Keyzone Classic", preset = "N2N Default", pluginsources = 7 },
    { selection_label = "POLY 24", search = "JS: POLY 24", preset = "", pluginsources = 7 },
    { selection_label = "Vital", search = "VST3i: Vital", preset = "", pluginsources = 16 },
    { selection_label = "WTFM Synth", search = "JS: WTFM Synth", preset = "" , pluginsources = 7 },
    { selection_label = "Yutani Mono Bass Synth", search = "JS: Yutani Mono Bass Synth", preset = "", pluginsources = 5 },
    { selection_label = "Select Other...", search = "", preset = "", pluginsources = 0 }
}

config.vst_fx_options = {
    { selection_label = "Blue Lexikan S2", search = "JS: CLAP: Surge", preset = "", pluginsources = 7 },
    { selection_label = "Bricastic2", search = "CLAP: Bricastic2", preset = "", pluginsources = 17 },
    { selection_label = "Deelay", search = "CLAP: Deelay", preset = "", pluginsources = 18 },
    { selection_label = "Delay Machine2", search = "JS: Delay Machine2", preset = "", pluginsources = 7 },
    { selection_label = "Lava Reverb", search = "JS: Lava Reverb", preset = "", pluginsources = 5 },
    { selection_label = "Lexican 2", search = "JS: Lexican 2", preset = "", pluginsources = 7 },
    { selection_label = "Matrix Delay S2", search = "Matrix Delay S2", preset = "", pluginsources = 7 },
    { selection_label = "Red Lexikan S2", search = "JS: Red Lexikan S2", preset = "", pluginsources = 7 },
    { selection_label = "Select Other...", search = "", preset = "", pluginsources = 0 }
}

config.letter_render_key = {
    { selection_label = "C", transpose = 0, flat = false },
    { selection_label = "C#", transpose = 1, flat = false },
    { selection_label = "Db", transpose = 1, flat = true },
    { selection_label = "D", transpose = 2, flat = false },
    { selection_label = "D#", transpose = 3, flat = false }, 
    { selection_label = "Eb", transpose = 3, flat = true },
    { selection_label = "E", transpose = 4, flat = false },
    { selection_label = "F", transpose = 5, flat = false },	
	{ selection_label = "F#", transpose = 6, flat = false },
    { selection_label = "Gb", transpose = 6, flat = true },
    { selection_label = "G", transpose = 7, flat = false },	
	{ selection_label = "G#", transpose = 8, flat = false },
    { selection_label = "Ab", transpose = 8, flat = true },	
    { selection_label = "A", transpose = 9, flat = false },	
	{ selection_label = "A#", transpose = 10, flat = false },
    { selection_label = "Bb", transpose = 10, flat = true },		
    { selection_label = "B", transpose = 11, flat = false }	
}

config.audiochoice = {
        { selection_label = "Audio ##"},
        { selection_label = "Ac. Guitar Audio ##"},
        { selection_label = "Elec. Guitar Audio ##"},
        { selection_label = "Bass Audio"},
        { selection_label = "Drums Audio"},
        { selection_label = "Piano Audio"},
        { selection_label = "BG Vocals ##"},
        { selection_label = "Lead Vocals"}
}


config.mode_options = {"Arpeggiated - N2N Arp", "Sustained", "N2N Drum Arranger", "LibreArp", "Saike MIDI Arp", "Blue ARP" }
config.drum_arp_mode_options = {"On/Off", "Every Section", "Every 4 Bars"}


-- "Default Template" Recipe
config.track_recipe = {
  { type = 0, ItemLabel = "Region Markers        Example:    Intro   Verse   Chorus   Verse   Chorus   Chorus    Outro", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = true, single = true, addchain = false },
  { type = 1, ItemLabel = "Nashville Number System Chord Chart                      Example in A:    1     4Maj7      2m7        5", IndentMIDI = -1, divider_before = true, Tr_divider_before = false, active = true, single = true, addchain = false  },
  { type = 6, ItemLabel = "Letter Based Chord Chart - Absolute                      Example in A:    A     DMaj7      F#m7       E", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = true, single = true, addchain = false  },
  { type = 5, ItemLabel = "Letter Based Chord Chart - Relative (Always C)           Example in A:    C     FMaj7      Dm7        G", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = false, single = true, addchain = false  },
  { type = 4, ItemLabel = "Letter Based Chord Chart - User Selection", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = false, single = true, vst_choice = config.letter_render_key[11], vst_list = config.letter_render_key, addchain = false },     -- ADD letter_render_key Select here!!!
  
  
  { type = 15, ItemLabel = "Relative Background Grid (C Major)         Useful for displaying all chord tones in all octaves when visible as a MIDI editor background track.", IndentMIDI = -1, divider_before = true, Tr_divider_before = false, active = true, single = true, addchain = false },
  { type = 7, ItemLabel = "Absolute Background Grid (Actual Key)", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = true, single = true, addchain = false },
  
  
  
  { type = 21, ItemLabel = "Black Key Live", IndentMIDI = -1, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_synth_options[8], vsti_list = config.vsti_synth_options, addchain = true },
  { type = 22, ItemLabel = "White Key Live", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = true, single = false, vsti_choice = config.vsti_synth_options[8], vsti_list = config.vsti_synth_options, addchain = true },
  
  
  -- INDENT THESE TO SHOW THEY GO TOGETHER
  
  -- TYPE SELECT Relative (default) | Absolute
  
  { type = 16, ItemLabel = "Chords", IndentMIDI = 0, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_synth_options[1], vsti_list = config.vsti_synth_options, mode = config.mode_options[2], addchain = true },
  { type = 16, ItemLabel = "Chords", IndentMIDI = 1, divider_before = false, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_synth_options[2], vsti_list = config.vsti_synth_options, mode = config.mode_options[1], addchain = true },
  { type = 17, ItemLabel = "Chords and Bass", IndentMIDI = 1, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_synth_options[6], vsti_list = config.vsti_synth_options, mode = config.mode_options[1], addchain = true},
  { type = 20, ItemLabel = "Bass", IndentMIDI = 1, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_bass_options[3], vsti_list = config.vsti_bass_options, mode = config.mode_options[2], addchain = true },
  { type = 20, ItemLabel = "Bass", IndentMIDI = 1, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_bass_options[1], vsti_list = config.vsti_bass_options, mode = config.mode_options[1], addchain = true },

  
  -- END INDENTATION
  
  { type = 31, ItemLabel = "N2N Drum Arranger - N2N Swing and Groove integration", IndentMIDI = -1, divider_before = true, Tr_divider_before = true, active = true, single = false, vsti_choice = config.vsti_drum_options[1], vsti_list = config.vsti_drum_options, preset_choice = config.drum_preset_options[64], preset_list = config.drum_preset_options, addchain = true },
  { type = 32, ItemLabel = "Create Cues for all N2N Drum Arranger tracks", IndentMIDI = -1, divider_before = true, Tr_divider_before = false, active = true, single = true, drum_arp_mode = config.drum_arp_mode_options[3], addchain = false },
  { type = 33, ItemLabel = "Create Cues for all N2N Arp tracks", IndentMIDI = -1, divider_before = false, Tr_divider_before = false, active = true, single = true, drum_arp_mode = config.drum_arp_mode_options[3], addchain = false },
  
  { type = 99, ItemLabel = "Empty Tracks for Audio", IndentMIDI = -1, divider_before = true, Tr_divider_before = true, active = true, single = false, audio_choice = config.audiochoice[1], audio_list = config.audiochoice, addchain = true },
	
  { type = 30, ItemLabel = "Shared FX with Sends on all N2N channels", IndentMIDI = -1, divider_before = true, Tr_divider_before = true, active = true, single = false, vst_choice = config.vst_fx_options[8], vst_list = config.vst_fx_options, addchain = false }
  
  
  

  
  
}



-- =========================================================================================
-- MASTER TRACK TEMPLATE CONFIGURATION
-- =========================================================================================
-- [1] = Track Name (String). ("REPLACEFX" inserts Synth name, "##" inserts instance number)
-- [2] = Show in TCP? (Boolean). True = Visible in Track Control Panel, False = Hidden.
-- [3] = Show in MCP? (Boolean). True = Visible in Mixer Control Panel, False = Hidden.
-- [4] = Clear Items? (1 = yes and 0 = no).
-- [5] = FX Chain (Table). { "Name", Enabled(bool), "Preset", SourceID }
-- [6] = Sends (Table). Keep as {} -- The Compiler routes these automatically!
--[7] = Is MIDI? (Legacy integer, safe to ignore).
-- [8] = Track Color (Table). { R, G, B }
-- [9] = Default Volume (Number). Linear scale (e.g., 1.0 is +0dB, 0.5 is -6dB).
-- =========================================================================================

-- Example of the new condensed format:
-- [0] = {"N2N Chord MIDI Source", true, false, 1, {}, {}, 1, {107, 138, 145}, 0},


config.track_table = {
    [1] = {
        [1] = {"N2N Nashville # Chart", true, false, 1, { 
            {"SwingProjectMIDI", true, nil, 0}
        }, {}, 0, {150, 150, 150}, 0}
    },
    [6] = {
        [1] = {"N2N Letter Chart", true, false, 1, {}, {}, 0, {150, 150, 150}, 0}
    },
    [5] = {
        [1] = {"N2N Rel. Letter Chart", true, false, 1, {}, {}, 0, {150, 150, 150}, 0}
    },
	[4] = {
        [1] = {"N2N Pref. Letter Chart", true, false, 1, {}, {}, 0, {150, 150, 150}, 0}
    },
    [7] = {
        [1] = {"N2N Abs. Bckgrd Grid", true, false, 1, {}, {}, 0, {150, 150, 150}, 0}
    },
    [15] = {
        [1] = {"N2N Rel. Bckgrd Grid", true, false, 1, {}, {}, 0, {150, 150, 150}, 0}
    },
	[21] = {
		[1] = {"Black Key Live", true, true, 0, {
            {"JS: Mood2Mode", true, nil, 0},
            {"REPLACEFX", true, "N2N Vital Default", 0}
        }, {}, 0, {207, 179, 160}, 0.4}
    },	
    [22] = {
		[1] = {"White Key Live", true, true, 0, {
            {"JS: Mood2Mode", true, nil, 0},
            {"REPLACEFX", true, "N2N Vital Default", 0}
        }, {}, 0, {207, 179, 160}, 0.4}
    },
    [16] = {[0] = {"N2N Chord MIDI Source", true, false, 1, {}, {}, 1, {107, 138, 145}, 0},
        [1] = {"N2N Arp Chord ##", true, true, 0, {
            {"JS: N2N Arp.jsfx", true, nil, 3},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.2},
        [2] = {"N2N Sust. Chord ##", true, true, 0, {
            {"Chords_Assign_N2N.jsfx", true, nil, 3},
            {"ReaCenterMIDIpitch", false, nil, 3},
            {"ReaPulsive-8ths", false, nil, 3},  
            {"SwingTrackMIDI", true, nil, 3},
            {"ThisTriggersThat", false, nil, 3},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.4},
        [3] = {"N2N DrumA. Chord ##", true, true, 0, {
            {"JS: N2N Drum Arranger", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.4},	
        [4] = {"N2N LibreA. Chord ##", true, true, 0, {
            {"VST3i: LibreArp", true, nil, 20},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.4},[5] = {"N2N SaikeMA. Chord ##", true, true, 0, {
            {"JS: Saike MIDI Arp", true, nil, 5},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.4},	
        [6] = {"N2N BlueA. Chord ##", true, true, 0, {
            {"VSTi: BlueARP", true, nil, 19},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {160, 198, 207}, 0.4}		
    },
    [17] = {
        [0] = {"N2N MIDI Source", true, false, 1, {}, {}, 1, {207, 160, 170}, 0}, 
        [1] = {"N2N Arp Chord-Bass ##", true, true, 0, {
            {"JS: N2N Arp.jsfx", true, nil, 3},  
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4},
        [2] = {"N2N Sust. Chord-Bass ##", true, true, 0, {
            {"HeadStart", true, nil, 3},
            {"ReaCenterMIDIpitch", false, nil, 3},
            {"ReaPulsive-8ths", false, nil, 3},  
            {"SwingTrackMIDI", true, nil, 3},
            {"ThisTriggersThat", false, nil, 3},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4},
        [3] = {"N2N DrumA. Chord-Bass ##", true, true, 0, {
            {"JS: N2N Drum Arranger", true, nil, 3},  
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4},
        [4] = {"N2N LibreA. Chord-Bass ##", true, true, 0, {
            {"VST3i: LibreArp", true, nil, 20},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4},
        [5] = {"N2N SaikeMA. Chord-Bass ##", true, true, 0, {
            {"JS: Saike MIDI Arp", true, nil, 5},  
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4},
        [6] = {"N2N BlueA. Chord-Bass ##", true, true, 0, {
            {"VSTi: BlueARP", true, nil, 19},  
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACE PRESET", 0}
        }, {}, 0, {198, 160, 207}, 0.4}
    },
    [20] = {
        [0] = {"N2N Bass MIDI Source", true, false, 1, {}, {}, 1, {107, 122, 145}, 0},
        [1] = {"N2N Arp Bass ##", true, true, 0, {
            {"JS: N2N Arp.jsfx", true, nil, 3},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.0},
        [2] = {"N2N Sust. Bass ##", true, true, 0, {
            {"Bass_Assign_N2N.jsfx", true, nil, 3},
            {"ReaCenterMIDIpitch", false, nil, 3},
            {"ReaPulsive-8ths", false, nil, 3},  
            {"SwingTrackMIDI", true, nil, 3},
            {"ThisTriggersThat", false, nil, 3},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.0},
        [3] = {"N2N DrumA. Bass ##", true, true, 0, {
            {"JS: N2N Drum Arranger", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.3},[4] = {"N2N LibreA. Bass ##", true, true, 0, {
            {"VST3i: LibreArp", true, nil, 20},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.0},	
        [5] = {"N2N SaikeMA Bass ##", true, true, 0, {
            {"JS: Saike MIDI Arp", true, nil, 5},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.0},
        [6] = {"N2N BlueA. Bass ##", true, true, 0, {
            {"VSTi: BlueARP", true, nil, 19},
			{"JS: Back2Key_N2N.jsfx", true, nil, 3},
            {"REPLACEFX", true, "REPLACEPRESET", 0}
        }, {}, 0, {160, 179, 207}, 1.0}
    },
    [31] = {
        [1] = {"N2N Drums REPLACEFX ##", true, true, 0, {
            {"JS:N2N Drum Arranger.jsfx", true, "REPLACEPRESET", 0},
            {"REPLACEFX", true, nil, 0},
			{"JS: 32_to_2_Downmix_N2N", true, nil, 0},
			{"JS: Cue_Pattern_Filter_N2N", true, nil, 0},
            {"JS:Violet Envelope Shaper S2", false, nil, 7}
        }, {}, 0, {144, 144, 144}, 1.3}
    },
	[30] = {
		[1] = {"N2N REPLACEFX", false, true, 0, {
			{"REPLACEFX", true, "REPLACEPRESET", 0},
			{"JS:ReEQ", true, nil, 2}
		}, {}, 1, {250, 250, 250}, 0.17}
    },
	
    [99] = {
        [1] = {"Audio ##", true, true, 0, {{"", false, nil, 3}}, {}, 1, {207, 207, 160}, 0},
        [2] = {"Ac. Guitar Audio ##", true, true, 0, {{"", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [3] = {"Elec. Guitar Audio ##", true, true, 0, {{"", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [4] = {"Bass Audio", true, true, 0, {{"Bass Station S2", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [5] = {"Drums Audio", true, true, 0, {{"", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [6] = {"Piano Audio", true, true, 0, {{"", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [7] = {"BG Vocals ##", true, true, 0, {{"", true, nil, 0}}, {}, 0, {207, 207, 160}, 1.0},
        [8] = {"Lead Vocals", true, true, 0, {
		{"JS: Vocoder S2", false, nil, 0},
		{"VST: ReaPitch", false, nil, 0},
		{"JS: Lime Deesser S2", false, nil, 0}
		}, {}, 0, {207, 207, 160}, 1.0}
    }
	
	
}

return config