-- @description numbers2notes_config
-- @version 1.0.4
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
    [1] = "Included with Reaper (Cockos/Stillwell). No download needed.",
    
    [2] = "ReaPack: 'ReaTeam Scripts' repository.",
    
    [3] = "ReaPack: 'Geraint's JSFX' repository. URL: https://github.com/geraintluff/jsfx-pad-synth",
    
    [4] = "ReaPack: 'Saike Tools' repository. URL: https://raw.githubusercontent.com/JoepVanlier/JSFX/master/index.xml",
    
    [5] = "Surge XT (Free Synth): https://surge-synthesizer.github.io/",
    
    [6] = "Sitala (Drum Sampler) for free version search the page for 'old version': https://decomposer.de/sitala/",
    
    [7] = "LibreARP (Arpeggiator): https://librearp.gitlab.io/",
    
    [8] = "Audio Damage 'Tattoo' (Legacy/Free): https://www.audiodamage.com/pages/free-and-legacy",
    
    [9] = "STFU (Volume Shaper): https://zeeks.app/",
    
    [10] = "Dragonfly Reverb: https://github.com/michaelwillis/dragonfly-reverb",
    
    [11] = "Airwindows (Calibre, Isolator, Holt, Tube, Drive): https://www.airwindows.com/",
    
    [12] = "ReaPack: 'Tukan Studios' repository. URL: https://raw.githubusercontent.com/TukanStudios/TUKAN_STUDIOS_PLUGINS/main/index2.xml",
    
    [13] = "Included N2N JSFX (Should be installed with this script).",
    
    [14] = "Audiolatry Drum8 2: https://audiolatry.gumroad.com/l/drum8",
    
    [99] = "Unknown Source."
}

-- 2. THE TRACK TABLE
-- Format: { "Track Name", Found?, TrackPtr, ClearItems?, {Plugins}, {Sends}, IsMidi?, Color, Vol }
-- Plugin Format: { "FX Name", Enabled(bool), Preset(string or nil), SourceID(int) }

config.track_table = {
    [0] = {"Track Name", false, nil, 1, {}, {}, 0, {0,0,0}, 0}, -- Header

    [1] = {"N2N # Chart", false, nil, 1, {
        {"SwingProjectMIDI", true, nil, 13}
    }, {}, 0, {100, 100, 100}, 0},

    [2] = {"N2N Letter Chart", false, nil, 1, {
        {"SwingProjectMIDI", true, nil, 13}
    }, {}, 0, {100, 100, 100}, 0},

    [3] = {"N2N Absolute Grid & Reverb", false, nil, 1, {
        {"JS:Lexikan", true, nil, 12} -- Tukan
    }, {}, 1, {250, 250, 250}, 0.17},

    [4] = {"N2N Relative Grid & Delay", false, nil, 1, {
        {"JS:Khaki Delay S2", true, nil, 12} -- Tukan
    }, {}, 1, {250, 250, 250}, 0},

    [5] = {"N2N Chords MIDI", false, nil, 1, {}, {6,7,8,9,10,11,12}, 1, {134, 172, 181}, 0},

    [6] = {"N2N Chord 1", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", false, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},  
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, "N2N_Chords", 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12}, -- Tukan
        {"Tube", false, nil, 11},  -- Airwindows
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12}, -- Tukan      
        {"Drive", false, nil, 11}, -- Airwindows
        {"JS:Saike SEQS", false, nil, 4},      
        {"JS:Limiter 3", false, nil, 12} -- Tukan
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [7] = {"N2N Chord 2", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", false, nil, 7},
        {"ReaPulsive-8ths", true, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, "N2N_Blips", 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},      
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4},      
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.2},

    [8] = {"N2N Chord 3", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, "N2N_Pie", 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},      
        {"Drive", false, nil, 11},
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [9] = {"N2N Chord 4", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, "N2N_Plucks", 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},      
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [10] = {"N2N Chord 5", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, nil, 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},      
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [11] = {"N2N Chord 6", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, nil, 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},      
        {"Drive", false, nil, 11},    
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [12] = {"N2N Chord 7", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, nil, 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},  
        {"Drive", false, nil, 11},    
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},  

    [13] = {"N2N Chord-Bass MIDI", false, nil, 1, {}, {14}, 1, {172, 134, 181}, 0}, 

    [14] = {"N2N Chord-Bass", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", true, nil, 7},
        {"ReaPulsive-8ths", false, nil, 13},  
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, nil, 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12}, 
        {"Tube", false, nil, 11},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 12},  
        {"Drive", false, nil, 11},
        {"JS:Saike SEQS", false, nil, 4},       
        {"JS:Limiter 3", false, nil, 12}
    }, {3, 4}, 0, {172, 134, 181}, 0.4},

    [15] = {"N2N Bass MIDI", false, nil, 1, {}, {16}, 1, {134, 153, 181}, 0},

    [16] = {"N2N Bass", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"LibreARP", false, nil, 7},
        {"ReaPulsive-halves", true, nil, 13},    
        {"SwingTrackMIDI", true, nil, 13},
        {"ThisTriggersThat", false, nil, 13},
        {"CLAP:Surge XT", true, "N2N_Bass", 5},
        {"STFU", false, nil, 9},
        {"JS:Guitar Amp", false, nil, 12},
        {"Tube", false, nil, 11},  
        {"JS:Dis-Treasure", false, nil, 12},  
        {"JS:LA-2KAN S2", false, nil, 12},
        {"JS:NC76 S2", false, nil, 12},
        {"JS:Compressor 2", false, nil, 12},  
        {"JS:ReEQ", true, nil, 2},  
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4},
        {"JS:Limiter 3", false, nil, 12} 
    }, {3, 4}, 0, {134, 153, 181}, 1.3},

    [17] = {"N2N Drums", false, nil, 0, {
        {"Tattoo", true, "35 Set - Old School", 8},
        {"SwingTrackMIDI", true, nil, 13},
        {"Sitala", false, nil, 6},
        {"Calibre", true, nil, 11},
        {"Holt", true, nil, 11},
        {"JS:Violet Envelope Shaper S2", true, "35 Set - Old School", 12},
        {"JS:Exciter+Sub", false, nil, 12},
        {"JS:Tape Recorder S2", false, nil, 12},  
        {"JS:Guitar Amp", false, nil, 12},  
        {"Tube", false, nil, 11},  
        {"JS:Dis-Treasure", true, nil, 12},  
        {"JS:LA-2KAN S2", false, nil, 12},
        {"JS:NC76 S2", false, nil, 12},
        {"JS:Compressor 2", false, nil, 12},
        {"JS:ReEQ", true, nil, 2},
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4}, 
        {"JS:Limiter 3", false, nil, 12} 
    }, {3,4}, 0, {144, 144, 144}, 4},

    [18] = {"Empty", false, nil, 0, {
        {"VST3i: Drum8 2 (audiolatry) (32 out)", false, nil, 14},
        {"Sitala", false, nil, 6},
        {"Calibre", true, nil, 11},
        {"Holt", true, nil, 11},
        {"JS:Tape Recorder S2", false, nil, 12},
        {"JS:Guitar Amp", false, nil, 12},  
        {"Tube", false, nil, 11},  
        {"JS:Dis-Treasure", true, nil, 12},  
        {"JS:LA-2KAN S2", false, nil, 12},
        {"JS:NC76 S2", false, nil, 12},
        {"JS:Compressor 2", false, nil, 12},
        {"JS:ReEQ", true, nil, 2},
        {"Drive", false, nil, 11},  
        {"JS:Saike SEQS", false, nil, 4}, 
        {"JS:Limiter 3", false, nil, 12} 
    }, {3,4}, 0, {222, 222, 222}, 1}
}


return config
