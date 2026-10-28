--------------------------------------------------------------------------------
-- Copyright 2026 Maurizio MARTINA Politecnico di Torino
--
-- Licensed under the Solderpad Hardware License, Version 2.1 (the "License");
-- you may not use this file except in compliance with the License.
-- You may obtain a copy of the License at http://solderpad.org/licenses/SHL-2.1
--
-- SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1
--
-- Unless required by applicable law or agreed to in writing, hardware and
-- materials distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
--------------------------------------------------------------------------------
-- Title      : Notes package
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : notes_pkg.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-16
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the package with the constants used to
-- define notes and scales both from audio/music perspective (sequences,
-- intervals, frequences, ...) and from a display/video perspective (bar positions,
-- colours, ...)
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;

package notes_pkg is

  -----------------------------------------------------------------------------
  -- Starting octave constants
  -----------------------------------------------------------------------------
  constant cC0_OCTAVE_I : integer := 0;
  constant cC1_OCTAVE_I : integer := 1;
  constant cC2_OCTAVE_I : integer := 2;
  constant cC3_OCTAVE_I : integer := 3;
  constant cC4_OCTAVE_I : integer := 4;
  constant cC5_OCTAVE_I : integer := 5;
  constant cC6_OCTAVE_I : integer := 6;
  constant cC7_OCTAVE_I : integer := 7;

  constant cC0_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC0_OCTAVE_I, 3);
  constant cC1_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC1_OCTAVE_I, 3);
  constant cC2_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC2_OCTAVE_I, 3);
  constant cC3_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC3_OCTAVE_I, 3);
  constant cC4_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC4_OCTAVE_I, 3);
  constant cC5_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC5_OCTAVE_I, 3);
  constant cC6_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC6_OCTAVE_I, 3);
  constant cC7_OCTAVE : unsigned(2 downto 0) := to_unsigned(cC7_OCTAVE_I, 3);

  -----------------------------------------------------------------------------
  -- Notes/semitones
  -----------------------------------------------------------------------------
  constant cMAX_NOTES : integer := 12;

  constant cC_NOTE : integer := 0;
  constant cCD_NOTE : integer := 1;
  constant cD_NOTE : integer :=  2;
  constant cDE_NOTE : integer := 3;
  constant cE_NOTE : integer := 4;
  constant cF_NOTE : integer := 5;
  constant cFG_NOTE : integer := 6;
  constant cG_NOTE : integer := 7;
  constant cGA_NOTE : integer := 8;
  constant cA_NOTE : integer := 9;
  constant cAB_NOTE : integer := 10;
  constant cB_NOTE : integer := 11;

  -----------------------------------------------------------------------------
  -- Preset scale (12 bit, bit[0]=C, bit[11]=B)
  -- '1' => note is present in the scale
  -----------------------------------------------------------------------------
  constant cTONIC_ONLY       : std_logic_vector(11 downto 0) := (0 => '1', others => '0'); -- C only
  constant cSCALE_CHROMATIC  : std_logic_vector(11 downto 0) := "111111111111";
  constant cSCALE_MAJOR       : std_logic_vector(11 downto 0) := "101010110101";  -- C D E F G A B
  constant cSCALE_MINOR_NAT   : std_logic_vector(11 downto 0) := "010110101101";  -- C D Eb F G Ab Bb
  constant cSCALE_DORIAN      : std_logic_vector(11 downto 0) := "011010101101";  -- C D Eb F G A Bb
  constant cSCALE_PHRYGIAN    : std_logic_vector(11 downto 0) := "010110101011";  -- C Db Eb F G Ab Bb
  constant cSCALE_LYDIAN      : std_logic_vector(11 downto 0) := "101011010101";  -- C D E F# G A B
  constant cSCALE_MIXOLYDIAN  : std_logic_vector(11 downto 0) := "011010110101";  -- C D E F G A Bb
  constant cSCALE_LOCRIAN     : std_logic_vector(11 downto 0) := "101101101011";  -- C Db Eb F Gb Ab A B
  constant cSCALE_PENTATONIC_MAJ  : std_logic_vector(11 downto 0) := "001010010101";  -- C D E G A
  constant cSCALE_PENTATONIC_MIN  : std_logic_vector(11 downto 0) := "010010101001";  -- C Eb F G Bb
  constant cSCALE_BLUES       : std_logic_vector(11 downto 0) := "010011101001";  -- C Eb F F# G Bb
  constant cSCALE_WHOLE_TONE  : std_logic_vector(11 downto 0) := "010101010101";  -- C D E F# G# A#
  constant cSCALE_DIMINISHED_TS  : std_logic_vector(11 downto 0) := "101101101101";  -- C D Eb F Gb Ab A B
  constant cSCALE_DIMINISHED_ST  : std_logic_vector(11 downto 0) := "011011011011";  -- C Db Eb E Gb G A Bb
  constant cSCALE_ARABIAN        : std_logic_vector(11 downto 0) := "010110110011";  -- C Db E F G Ab Bb

  -----------------------------------------------------------------------------
  -- Position of the scales in the preset table (SW[9:6] = 0..15)
  -----------------------------------------------------------------------------
  constant cTONIC_POS : integer := 0;
  constant cMINOR_NAT_POS : integer := 1;
  constant cMAJOR_POS : integer := 2;
  constant cDORIAN_POS : integer := 3;
  constant cPHRYGIAN_POS : integer := 4;
  constant cLYDIAN_POS : integer := 5;
  constant cMIXOLYDIAN_POS : integer := 6;
  constant cLOCRIAN_POS : integer := 7;
  constant cPENTATONIC_MAJ_POS : integer := 8;
  constant cPENTATONIC_MIN_POS : integer := 9;
  constant cBLUES_POS : integer := 10;
  constant cWHOLE_TONE_POS : integer := 11;
  constant cDIMINISHED_TS_POS : integer := 12;
  constant cDIMINISHED_ST_POS : integer := 13;
  constant cARABIAN_POS : integer := 14;
  constant cCHROMATIC_POS : integer := 15;

  -- Preset table
  type scale_table_t is array(0 to 15) of std_logic_vector(11 downto 0);
  constant cSCALE_TABLE : scale_table_t := (
    cTONIC_POS => cTONIC_ONLY,                     -- 0
    cMINOR_NAT_POS => cSCALE_MINOR_NAT,            -- 1
    cMAJOR_POS => cSCALE_MAJOR,                    -- 2
    cDORIAN_POS => cSCALE_DORIAN,                  -- 3
    cPHRYGIAN_POS => cSCALE_PHRYGIAN,              -- 4
    cLYDIAN_POS => cSCALE_LYDIAN,                  -- 5
    cMIXOLYDIAN_POS => cSCALE_MIXOLYDIAN,          -- 6
    cLOCRIAN_POS => cSCALE_LYDIAN,                 -- 7
    cPENTATONIC_MAJ_POS => cSCALE_PENTATONIC_MAJ,  -- 8
    cPENTATONIC_MIN_POS => cSCALE_PENTATONIC_MIN,  -- 9
    cBLUES_POS => cSCALE_BLUES,                    -- 10
    cWHOLE_TONE_POS => cSCALE_WHOLE_TONE,          -- 11
    cDIMINISHED_TS_POS => cSCALE_DIMINISHED_TS,    -- 12
    cDIMINISHED_ST_POS => cSCALE_DIMINISHED_ST,    -- 13
    cARABIAN_POS => cSCALE_ARABIAN,                -- 14
    cCHROMATIC_POS => cSCALE_CHROMATIC,            -- 15
    others => cSCALE_MAJOR
    );

  -- Scale/note flags
  constant cIS_TONAL : std_logic := '0';
  constant cIS_MODAL : std_logic := '1';
  constant cIS_SHARP : std_logic := '0';
  constant cIS_FLAT : std_logic := '1';

  -----------------------------------------------------------------------------
  -- Note display geometry
  -----------------------------------------------------------------------------
  constant cMAX_BARS : integer := 12;
  constant cMAX_ACTIVE_OCTAVES_IDX : integer := 3;

  type tPalette_Pos_Array is array (0 to cMAX_BARS-1) of integer range 0 to cMAX_BARS-1;

  -----------------------------------------------------------------------------
  -- Display colours
  -----------------------------------------------------------------------------

  type rColor is record
    R : unsigned(7 downto 0);
    G : unsigned(7 downto 0);
    B : unsigned(7 downto 0);
  end record;

  type tPalette is array(0 to cMAX_BARS-1) of rColor;

  constant cPALETTE : tPalette := (
    0  => (R => to_unsigned(232, 8), G => to_unsigned(49,  8), B => to_unsigned(106, 8)), -- C  (Coral)
    1  => (R => to_unsigned(238, 8), G => to_unsigned(94,  8), B => to_unsigned(90,  8)), -- C# (Orange)
    2  => (R => to_unsigned(245, 8), G => to_unsigned(150, 8), B => to_unsigned(74,  8)), -- D  (Pumpkin)
    3  => (R => to_unsigned(245, 8), G => to_unsigned(217, 8), B => to_unsigned(74,  8)), -- D# (Yellow)
    4  => (R => to_unsigned(185, 8), G => to_unsigned(217, 8), B => to_unsigned(80,  8)), -- E  (Lime)
    5  => (R => to_unsigned(126, 8), G => to_unsigned(217, 8), B => to_unsigned(87,  8)), -- F  (Green)
    6  => (R => to_unsigned(78,  8), G => to_unsigned(217, 8), B => to_unsigned(130, 8)), -- F# (Mint)
    7  => (R => to_unsigned(78,  8), G => to_unsigned(199, 8), B => to_unsigned(176, 8)), -- G  (Water)
    8  => (R => to_unsigned(78,  8), G => to_unsigned(160, 8), B => to_unsigned(217, 8)), -- G# (Cyan)
    9  => (R => to_unsigned(90,  8), G => to_unsigned(100, 8), B => to_unsigned(245, 8)), -- A  (Blue)
    10 => (R => to_unsigned(160, 8), G => to_unsigned(80,  8), B => to_unsigned(245, 8)), -- A# (Violet)
    11 => (R => to_unsigned(232, 8), G => to_unsigned(60,  8), B => to_unsigned(200, 8))  -- B  (Fuchsia)
    );

  constant cBORDER : rColor := (R => to_unsigned(0, 8), G => to_unsigned(0, 8), B => to_unsigned(0, 8));
  constant cBACKGROUND : rColor := (R => to_unsigned(10, 8), G => to_unsigned(26, 8), B => to_unsigned(58, 8));

  -----------------------------------------------------------------------------
  -- Note names font
  -----------------------------------------------------------------------------
  -- Vertical threshold to start displaying note names
  constant cVTHR1 : integer := 450;     -- space
  constant cVTHR2 : integer := 463;     -- font
  constant cVTHR3 : integer := 470;     -- space
  -- Font types
  type tFont6x7 is array (0 to 6) of std_logic_vector(0 to 5);
  type tFont3x7 is array (0 to 6) of std_logic_vector(0 to 2);

  -- Note names font ROMs (6x7)
  constant cFONT_A : tFont6x7 := ("001100", "010010", "100001", "111111", "100001", "100001", "100001");
  constant cFONT_B : tFont6x7 := ("111100", "100010", "100010", "111100", "100010", "100010", "111100");
  constant cFONT_C : tFont6x7 := ("001110", "010001", "100000", "100000", "100000", "010001", "001110");
  constant cFONT_D : tFont6x7 := ("111100", "100010", "100001", "100001", "100001", "100010", "111100");
  constant cFONT_E : tFont6x7 := ("111111", "100000", "100000", "111100", "100000", "100000", "111111");
  constant cFONT_F : tFont6x7 := ("111111", "100000", "100000", "111100", "100000", "100000", "100000");
  constant cFONT_G : tFont6x7 := ("001110", "010001", "100000", "101111", "100001", "010001", "001110");

  -- Sharp/Flat font ROMs (3x7)
  constant cFONT_SHARP : tFont3x7 := ("101", "111", "101", "111", "101", "000", "000");
  constant cFONT_FLAT  : tFont3x7 := ("100", "100", "100", "110", "101", "110", "000");

  type tFont6x7_array is array (0 to cMAX_BARS-1) of tFont6x7;

  -- Note names font array ROM with Sharp
  constant cFont6x7_array_sharp : tFont6x7_array := (
    0 => cFONT_C,
    1 => cFONT_C,
    2 => cFONT_D,
    3 => cFONT_D,
    4 => cFONT_E,
    5 => cFONT_F,
    6 => cFONT_F,
    7 => cFONT_G,
    8 => cFONT_G,
    9 => cFONT_A,
    10 => cFONT_A,
    11 => cFONT_B
    );

  -- Note names font array ROM with Flat
  constant cFont6x7_array_flat : tFont6x7_array := (
    0 => cFONT_C,
    1 => cFONT_D,
    2 => cFONT_D,
    3 => cFONT_E,
    4 => cFONT_E,
    5 => cFONT_F,
    6 => cFONT_G,
    7 => cFONT_G,
    8 => cFONT_A,
    9 => cFONT_A,
    10 => cFONT_B,
    11 => cFONT_B
    );

  -----------------------------------------------------------------------------
  -- TOUCH colors
  -----------------------------------------------------------------------------
  constant cMAGENTA : rColor := (R => to_unsigned(255, 8), G => to_unsigned(0, 8), B => to_unsigned(255, 8));
  constant cCIANO : rColor := (R => to_unsigned(0, 8), G => to_unsigned(255, 8), B => to_unsigned(255, 8));
  constant cLIME : rColor := (R => to_unsigned(50, 8), G => to_unsigned(255, 8), B => to_unsigned(50, 8));
  constant cORANGE : rColor := (R => to_unsigned(255, 8), G => to_unsigned(165, 8), B => to_unsigned(0, 8));
  constant cWHITE : rColor := (R => to_unsigned(240, 8), G => to_unsigned(240, 8), B => to_unsigned(240, 8));

  type tTouchColor_array is array (0 to cN_MTL2_TOUCH-1) of rColor;
  constant cTouchColor_array : tTouchColor_array := (
    0 => cMAGENTA,
    1 => cCIANO,
    2 => cLIME,
    3 => cORANGE,
    4 => cWHITE
    );

  -----------------------------------------------------------------------------
  -- DDS
  -----------------------------------------------------------------------------

  constant cNBIT_DDS_Phase : integer := 24;
  constant cNBIT_DDS_PhAcc : integer := 32;

end package notes_pkg;
