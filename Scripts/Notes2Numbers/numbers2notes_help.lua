-- @description numbers2notes_help
-- @version 1.0.6
-- @noindex
-- @author Rock Kennedy
-- @about
--   # numbers2notes_help
--   Numbers2Notes Support File.
-- @changelog
--   + Removed indexing
--   + Forced Update



local help =
{

chart_entry = [[]],

Lyric_output = "All entered lyrics can be viewd here after rendering.",

BIAB_output = [[
FUTURE FEATURE - Band in a Box Support Planned.

Hopefully when this feature is added you will be able 
to copy information rendered here and paste it into BIAB.

https://www.pgmusic.com/
]],

Onemotion_output = [[
FUTURE FEATURE - OneMotion.com Support Planned.

Hopefully when this feature is added you will be able 
to copy information rendered here and paste it into the 
'Edit All' section of Onemotion.Com's Chord Player

Onemotion.com is currently a free service.

https://www.onemotion.com/chord-player/
]],

Chordsheet_output = [[
FUTURE FEATURE - Chordsheet.com Support Planned.

Hopefully in when the feature is added you will be able 
to copy information rendered here and paste it into 
Chordsheet.com's editor for creating Chord Charts.

Chordsheet.com is currently a free service.

https://www.chordsheet.com/song/new
]],

Sample_song = [[
Title: Some New Day
Writer: Kevin Martin
BPM: 90
Key: G
Swing: 0
Form: I V C V C C O

{I}
1add2               4add2               1add2               5
[1 1/7 6m 6m/5]     4add2               [1 1/7 6m 6m/5]     5

{V}
[3(6m) 5(2m7)]      1add2               [3(6m) 5(2m7)]      1add2
[3(6m) 5(2m7)]      4add2               1add2               5sus
[3(6m) 5(2m7)]      1add2               [3(6m) 5(6m7)]      1add2
[3(6m) 5(2m7)]      4add2               5sus                5         

{C}
[3(1) 5(5)]         [3(6m) 5(4)]        [3(1) 5(5)]         [3(6m) 5(4)]                  
[3(1) 5(5)]         [3(6m) 5(4)]        [3(1) 5(5)]         [3(6m) 5(4)]                     

{O}
[3(1) 5(5)]         [3(6m) 5(4)]        [3(1) 5(5)]         [3(6m) 5(4)]
4[4]
     
]],

Template = [[
Title: 
Writer: 
BPM: 
Key: 
Swing: 
Form: I V C V C C O

{I}


{C}


{V}


{O}


]],
Codes_out = [[
Title:		Title must be on it's own line
BPM:		Tempo in Beats per minute

Start: 		Starting Point in Bars:Beats


BODY CODES
K =       Key
BPM =     Tempo in Beats Per Minute (Use ! to set Reaper Tempo - example T=90!)
TS =      Time Signature (assumed to be 4/4)
G =       Groove



U8 = up an octave
D8 = down an octave
CU8 = up an octave
CD8 = down an octave
BU8 = up an octave
BD8 = down an octave

U3 = DOES NOT TRANSPOSE RATHER IT RAISES NOTES UP TO A VOICING ABOUT A THIRD HIGHER
DN = N can be replaced with any number.


TEXT CODES
L =       Lyrics
M =       Marker
R =       Region Marker

DYNAMIC CODES
VEL =     Velocity
]],

Code_help = [[

HEADER CODES - THESE CODES MUST BE ON THEIR OWN LINE AT THE TOP

Key:		Major Keys only!
			For minor use the Relative Major key and focus on 6m.
			This is common practice in Nashville Number System
				
				Examples:
				Key: G
				Key: Bb
				Key: C#

Form:     	Song Form
				- Separate sections with commas.
				- In the song itself place sections in braces.
				- Place custom quotes in quotes in the header.

				Common Form Examples:
				Form: C V C V C C
				Form: I C V C V C C O
				Form: V C V C C
				Form: I V C V C C O
				Form: I V C V C B C O
				
				Other Examples
				Form: 1 2 1 3 1 4 1 5 1
				Form: "Spoken Intro" V C V C "Sax Solo" C
				Form: I "Verse 1" C "Verse 2" C C "24 Bar Fadeout"
]],

Section_out = [[
						-- Count In
{#} 

						-- Section Marks	
{$1} = {Section 1}
{$2} = {Section 2}
{$9} = {Section 9}
{$A} = {Section A}
{$B} = {Section B}
{$Z} = {Section Z}



]],
Section_help = [[
SECTIONS - Section heading codes must be on their own line!

Single Character Sections
	{A}			{N}			{X}
	{E}			{Q}			{Y}
	{J}			{T}			{Z}
	{K}			{U}
	{L}			{W}

Special Single Character Sections - With autoreplaced names
	{B} = {Bridge}
	{C} = {Chorus}
	{D} = {Drop}
	{F} = {Fadeout}
	{I} = {Intro}
	{M} = {Middle 8}
	{O} = {Outro}
	{P} = {Pre-Chorus}
	{R} = {Ramp}
	{S} = {Solo}
	{V} = {Verse}

Single Digit Examples:		Custom Section Marks:
	{1}							{Interlude}
	{2}							{Half Verse}
	{9}							{Anything you want}

]],
Chord_out = [[

SPECIAL CHORD PREFIXES

<         1/8th Push
<<        16th Push
t<        Triplet Push
2t< 	  Two-Triplet Push
<.	 	  Dotted Eighth Push


x         click - no chord


SPECIAL CHORD SUFFIXES

!         Accent
_         Hold
:         Hit
~         Tie


-         Rest (When found alone!)
.         Continue Chord (When found alone!)
\         Repeat and Restrike the Chord (When needed in subdivisions of groove)
]],
Chord_help = [[

CHORD NOTATION

-     rest, no chord
1     Major Chord built on 1 (tonic - ex. C in the Key of C)
2m    Minor Chord built on scale step 2 (ex. Dm in the Key of C)
2-    Minor Chord built on scale step 2 (ex. Dm in the Key of C)
3m7   Minor 7 Chord build on scale step 3 (ex. Em7 in the Key of C)
4j7   Major 7 Chord build on scale step 4 (ex. Fmaj7 in the Key of C)
57    Dominant 7 Chord Build on scale 5 step (ex. G7 in the Key of C)


STAND ALONE SYMBOLS

%         Repeat Bar (when found alone!)


CHORD OVER BASS

		Examples in the key of C:
			
			1/5     =   C chord over a G in the bass
			2m7/3   =   Dm7 over E in the bass
			5/4     =   G chord over F in the bass
			
Scroll down for the complete list of supported chord types.

CHORD NAME          CODE OPTIONS

Major               No symbol needed
Unison              u
sus2                sus2
sus2 7              sus27, 7sus2
sus2 maj7           sus2maj7, sus2j7, maj7sus2, j7sus2
sus24               sus24		
sus24 7             sus247, 7sus24
sus24 maj7          sus24maj7, sus24j7, maj7sus24, j7sus24
minor               m, -
minor add 2         madd2, -add2
minor add b2        maddb2, -addb2
minor add 4         madd4, -add4
minor 6             m6, -6
minor b6            mb6, -b6
minor 7             m7, -7
minor maj7          mmaj7, mj7, -maj7, -j7
minor 9             m9, -9
minor 11            m11, -11
minor 13            m13, -13
add 2               add2
add b2              addb2
add 4               add4
6                   6
maj7                maj7, j7
9                   9
b9                  b9
11                  11
13                  13
(sus 4)             sus
sus7                sus7, 7sus
sus47               sus47, 7sus4, 7sus
(7sus)              sus47, 7sus4, 7sus
(7sus4)             sus47, 7sus4, 7sus
sus maj7            susmaj7, susj7, maj7sus, maj7sus4, j7sus4, j7sus
sus4 maj7           susmaj7, susj7, maj7sus, maj7sus4, j7sus4, j7sus
(maj7 sus)          susmaj7, susj7, maj7sus, maj7sus4, j7sus4, j7sus
diminished          dim, o
b5                  dim
dim7                dim7, o7
fully diminished 7  dim7, o7
half diminished 7   hdim7, %, %7
5                   5
powerchord          5
57                  57
5maj7               5maj7, 5j,7
59                  59
5b9                 5b9
augmented           aug, +
+                   aug, +
augmented 7         aug7, +7, 7aug, 7+
7 augmented         aug7, +7, 7aug, 7+
augmented maj 7     augmaj7, augj7, +maj7, +j7, maj7aug, j7aug, maj7+,
						 j7aug+
maj7 augmented      augmaj7, augj7, +maj7, +j7, maj7aug, j7aug, maj7+,
						 j7aug+

]],

Rhythn_out = [[


1_                HELD BAR (one bar with a whole note of 1 chord)
1_ [1 4]          HELD BAR and SPLIT BAR (A whole note of the 1 chord followed by 2 beats of 1 and 2 beats of 4)
],
1_~ [1_ 4]        HELD BAR TIED TO SPLIT BAR (6 beats of 1 and 2 beats of 4)
]],

Rhythm_help = [[
RHYTHMIC NOTATION - BARS -------------------------------------------

FULL BAR
1              (full bar of 1)
 
SPLIT BAR
[1 4]          (two beats of 1 and 2 beats of 4)   
     
SPLIT BAR WITH REST
[1 r]          (two beats of 1 and 2 beats of rest)

MULTI BARS
4[5]           (four bars of 5)
2[1 4 1]       (two bars comprising three whole note triplets) 

UNEVEN SPLIT BARS 
[2(1) 4 5]     (two beats of 1, a beat of 4, and a beat of 5)
[3m 2(6m) 5]   (one beat of 3m, two beats of 6m, and a beat of 5)
[3(1) 5(6m)]   (3 eighth notes of 1, 5 eighth notes of 6m)

EVEN SEPTUPLET SPLIT BAR
[5 1 4 b7 b3 b6 b2]

RHYTHMIC NOTATION - PUSHES -------------------------------------------

<		Eighth note push - (half beat) early
				Following chord will be an eighth note early.
				
<<		Sixteenth note push - (quarter beat) early
				Following chord will be a sixteenth note early.

Example 		1	<2m   =    3 1/2 Beats of 1 and 4 1/2 Beats of 2m. 

Be careful using the pushes!!!!!!  
Do not "borrow" more from the previous chord than it's value.

For example this rhythm will cause a crash or at least an error.

[ 1  2m  3m  (4  5)]   <6m

Why? 
Because this indicates you want the 5 and 6m to happen at the same time.

RHYTHMIC NOTATION - BEATS -------------------------------------------

SPLIT BEAT
(1 2m)         (Two eighths - 1/2 beat of 1 and 1/2 beat of 2m)

SPLIT BEAT WITH REST 
(6m7 r)        (Eighth note of 6m7 and eighth rest)

SPLIT BEAT 
(1 5 4)        (Triplet split) 
               (1/3 beat of 1, 1/3 beat of 5, 1/3 beat of 4)

UNEVEN SPLIT BEAT 
(2(1) 4)       (2/3 beat of 1, and 1/3 beat of 4)

RHYTHMIC NOTATION - SUBDIVISIONS OF THE BEAT ------------------------
       
SPLIT BEAT WITH SUBDIVISIONS
(1 (2m 1 2m))  (eighth note of 1, 16th note triplets on 2m, 1, and 2m)

]],

Groove_help = [[

GROOVE NOTATION                     (express patterns override groove)

1            Whole Note Pulse
4            1/4 Note Pulse
8            1/8th Note Pulse (default)
16           16th Note Pulse
8T           1/8th Note Triplet Pulse
16T          16th Note Triplet Pulse
8.8 (55:45)           1/8th Note Pulse with a 55% / 45% swing
8.8 (55.100:45.80)    1/8th Note Pulse with a 55% / 45% swing with the first 8th at a velocity of 100 and the second at 80
8.8.8.8.8.8.8.8 (50.110:50.70 : 50.80:50.50 : 50.100:50.60 : 50.80:50.50)    Every beat of Bar with difined length and velocity


OTHER EXAMPLE GROOVES
16.16.16.16 (30:30:20:20)
16.16.16.16 (30.110:30.80.:20.100:20.70)
16.8.16 (20.60.20)
8.8.8.8.8.8.8.8 (50.120:50.70 : 50.80:50.50 : 50.100:50.60 : 50.80:50.50) 8.8.8.8.8.8.8.8 (50.110:50.70 : 50.80:50.50 : 50.100:50.60 : 50.80:50.50)

]],

Removed_stuff = [[
				
t<		Triplet push - (1/3 beat) early
				Following chord will be an eighth note triplet early.
				
2t<		Two triplet push - (2/3 beat) early
				Following chord will be two eighth note triplets early.
				
<.		Dottend eighth push - (3/4 beat) early
				Following chord will be a dottend eighth note early.



]]




}

return help
