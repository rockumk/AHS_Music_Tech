-- @description numbers2notes_config
-- @version 1.5
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

    [99] = "Unknown Source."
}

-- 2. THE TRACK TABLE
-- Format: { "Track Name", Found?, TrackPtr, ClearItems?, {Plugins}, {Sends}, IsMidi?, Color, Vol }
-- Plugin Format: { "FX Name", Enabled(bool), Preset(string or nil), SourceID(int) }

config.track_table = {
    [0] = {"Track Name", false, nil, 1, {}, {}, 0, {0,0,0}, 0}, -- Header

    [1] = {"N2N # Chart", false, nil, 1, {
        {"SwingProjectMIDI", true, nil, 3}
    }, {}, 0, {100, 100, 100}, 0},

    [2] = {"N2N Letter Chart", false, nil, 1, {
    }, {}, 0, {100, 100, 100}, 0},

    [3] = {"N2N Absolute Grid & Reverb", false, nil, 1, {
        {"JS:Lexikan", true, nil, 7} -- Tukan
    }, {}, 1, {250, 250, 250}, 0.17},

    [4] = {"N2N Relative Grid & Delay", false, nil, 1, {
        {"JS:Khaki Delay S2", true, nil, 7} -- Tukan
    }, {}, 1, {250, 250, 250}, 0},

    [5] = {"N2N Chords MIDI", false, nil, 1, {}, {6,7,8,9,10,11,12}, 1, {134, 172, 181}, 0},

    [6] = {"N2N Chord 1", false, nil, 0, {
        {"HeadStart", true, nil, 3},
        {"ReaCenterMIDIpitch", false, nil, 3},
        {"ReaPulsive-8ths", false, nil, 3},  
        {"SwingTrackMIDI", true, nil, 3},
        {"ThisTriggersThat", false, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Chords", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7}, -- Tukan
        {"Tube", false, nil, 9},  -- Airwindows
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7}, -- Tukan      
        {"Drive", false, nil, 9}, -- Airwindows
        {"JS:Saike SEQS", false, nil, 5},      
        {"JS:Limiter 3", false, nil, 7} -- Tukan
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [7] = {"N2N Chord 2", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Blips", 8},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},  
        {"JS:Saike SEQS", false, nil, 5},
        {"STFU", false, nil, 11},		
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.2},

    [8] = {"N2N Chord 3", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Plucks", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},  
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [9] = {"N2N Chord 4", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Plucks", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [10] = {"N2N Chord 5", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Plucks", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [11] = {"N2N Chord 6", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Plucks", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},

    [12] = {"N2N Chord 7", false, nil, 0, {
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Plucks", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 172, 181}, 0.4},  

    [13] = {"N2N Chord-Bass MIDI", false, nil, 1, {}, {14}, 1, {172, 134, 181}, 0}, 

    [14] = {"N2N Chord-Bass", false, nil, 0, {
        {"HeadStart", true, nil, 13},
        {"ReaCenterMIDIpitch", false, nil, 13},
        {"JS: N2N Arp", true, nil, 13},
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
        {"JS: N2N Arp", true, nil, 3},
        {"CLAP:Surge XT", true, "N2N_Bass", 8},
        {"STFU", false, nil, 11},
        {"JS:Guitar Amp", false, nil, 7},
        {"Tube", false, nil, 9},
        {"JS:ReEQ", true, nil, 2},
        {"JS:Compressor 2", false, nil, 7},      
        {"Drive", false, nil, 9},
        {"JS:Saike SEQS", false, nil, 5},       
        {"JS:Limiter 3", false, nil, 7}
    }, {3, 4}, 0, {134, 153, 181}, 1.3},

    [17] = {"N2N Drums", false, nil, 0, {
        {"JS:N2N Drum Arranger", true, "N2N Default", 13},
        {"Pro Punk Drums (Pro Punk DSP) (16 out)", true, nil, 13},
		{"JS:ReEQ", true, nil, 2},
        {"JS:Violet Envelope Shaper S2", false, nil, 12},
        {"JS:VariBus Comp S2", true, nil, 12},
		
        {"JS:Tape Recorder S2", false, nil, 12},  
        {"JS:Saike SEQS", false, nil, 4}, 
        {"JS:Limiter 3", false, nil, 12} 
    }, {3,4}, 0, {144, 144, 144}, 4}

}


return config




