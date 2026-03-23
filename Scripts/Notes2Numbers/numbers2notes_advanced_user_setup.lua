-- @description numbers2notes_advanced_user_setup
-- @version 1.5.6
-- @noindex
-- @author Rock Kennedy
-- @about
--   advanced_user_setup file for Numbers2Notes.
--   Contains common FX chain.
-- @changelog
--   + Links Updated

local advanced_user_setup = {}

advanced_user_setup.commonchain = {
    {"JS: PreAmp", false, nil, 7},
    {"JS: ExpGate 2", false, nil, 7},
    {"JS: NC76 S2", false, nil, 7},
    {"JS: LA-2KAN S2", false, nil, 7},
    {"JS: Compressor 3", false, nil, 7},
    {"JS: Saturation S2", false, nil, 7},
    {"JS: Orange EQ S2", false, nil, 7},
    {"JS:ReEQ", true, nil, 2},
    {"JS: Delay Machine2", false, nil, 7},
    {"JS:Guitar Amp", false, nil, 7},
    {"JS:Saike SEQS", false, nil, 5},
    {"JS: SC Filter", false, nil, 7},
    {"JS: SumChannel S2", true, nil, 7},
    {"JS: Limiter 3", false, nil, 7}
}

return advanced_user_setup
