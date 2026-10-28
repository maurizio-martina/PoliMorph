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
-------------------------------------------------------------------------------
-- Title      : Control Decoder
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : control_decoder.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2026-10-16
-- Last update: 2026-10-16
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: Reads switches and push-buttons to generate control parameters
-- according to the following mapping:
-- SW[3:0]  -> Tonic selection (0=C, 1=C#, 2=D, ... 11=B)
-- SW[5:4]  -> Number of octaves
--             00 -> 2 octaves (24 semitones, 384 px)
--             01 -> 3 octaves (36 semitones, 576 px)
--             1- -> 4 octaves (48 semitones, 768 px)
-- SW[9:6]  -> Scale preset (SCALE_TABLE index)
-- KEY[3]   -> sharp/flat toggle of the tonic note (and so of the scale notes)
-- KEY[2]   -> pitch-lock: lock finger position on note or leave unlocked
-- KEY[1:0] -> Starting octave (up/down counter)
--             Reset / default : C3  (octave_start = 3)
--             KEY[1] -> up C3 -> C4 -> C5 sat
--             KEY[0] -> down C3 -> C2 -> C1 sat
-------------------------------------------------------------------------------
-- Output octave_start: 1=C1, 2=C2, 3=C3, 4=C4, 5=C5
-- NOTE: C7 is the maximum, so if C5 is the starting octave, there will be 2
-- octaves independently of SW[5:4]
-------------------------------------------------------------------------------
-- Copyright (c) 2026
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.notes_pkg.all;

entity control_decoder is
  port (
    CLK          : in  std_logic;
    RST_n        : in  std_logic;
    SW           : in  std_logic_vector(9 downto 0);
    KEY          : in  std_logic_vector(3 downto 0);
    ROOT_NOTE    : out unsigned(3 downto 0);
    N_OCTAVES    : out unsigned(2 downto 0);
    OCTAVE_START : out unsigned(2 downto 0);
    SCALE_MASK   : out std_logic_vector(11 downto 0);
    SCALE_LEN    : out unsigned(3 downto 0);
    SCALE_TYPE   : out std_logic_vector(1 downto 0);
    N_SEMITONES  : out unsigned(5 downto 0);
    PALETTE_POS  : out tPalette_Pos_Array;
    PITCH_LOCKED : out std_logic
    );
end entity;

architecture rtl of control_decoder is

  -- Get the Scale Table from the Scale index
  function fGetScale(
    signal sw_scale : std_logic_vector(3 downto 0))
    return std_logic_vector is
  begin
    return cSCALE_TABLE(to_integer(unsigned(sw_scale)));
  end function;

  -- Get scale type (Tonal/Modal) (Sharp/Flat)
  function fGetScaleType (
    signal Mask_Sel      : std_logic_vector(3 downto 0);
    signal Root_Note_Val : unsigned(3 downto 0);
    signal sharp_flat : std_logic)
    return std_logic_vector is
    variable vScale_Type : std_logic_vector(1 downto 0);
  begin  -- function fGetScaleType
    case to_integer(unsigned(Mask_Sel)) is
      -- Tonic only
      when cTONIC_POS =>
        vScale_Type(1) := cIS_TONAL;
        vScale_Type(0) := sharp_flat;
      -- Minor natural or Pentatonic minor or Blues or Diminished
      when cMINOR_NAT_POS | cPENTATONIC_MIN_POS | cBLUES_POS | cDIMINISHED_TS_POS | cDIMINISHED_ST_POS =>
        vScale_Type(1) := cIS_TONAL;
        case to_integer(Root_Note_Val) is
          when cE_NOTE | cB_NOTE | cA_NOTE =>
            vScale_Type(0) := cIS_SHARP;
          when cC_NOTE | cD_NOTE | cF_NOTE | cG_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Major or Pentatonic major or Whole tone
      when cMAJOR_POS | cPENTATONIC_MAJ_POS | cWHOLE_TONE_POS =>
        vScale_Type(1) := cIS_TONAL;
        case to_integer(Root_Note_Val) is
          when cF_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when cC_NOTE | cD_NOTE | cE_NOTE | cG_NOTE | cA_NOTE | cB_NOTE =>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Dorian
      when cDORIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cF_NOTE | cG_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when cD_NOTE | cE_NOTE | cA_NOTE | cB_NOTE=>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Phrygian
      when cPHRYGIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cD_NOTE | cF_NOTE | cG_NOTE | cA_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when cE_NOTE | cB_NOTE=>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Lydian
      when cLYDIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cD_NOTE | cE_NOTE | cF_NOTE | cG_NOTE | cA_NOTE | cB_NOTE =>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Mixolydian
      when cMIXOLYDIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cF_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when cD_NOTE | cE_NOTE | cG_NOTE | cA_NOTE | cB_NOTE =>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Locrian
      when cLOCRIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cD_NOTE | cE_NOTE | cF_NOTE | cG_NOTE | cA_NOTE | cB_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Arabian
      when cARABIAN_POS =>
        vScale_Type(1) := cIS_MODAL;
        case to_integer(Root_Note_Val) is
          when cC_NOTE | cF_NOTE | cG_NOTE | cA_NOTE =>
            vScale_Type(0) := cIS_FLAT;
          when cD_NOTE | cE_NOTE | cB_NOTE =>
            vScale_Type(0) := cIS_SHARP;
          when others =>
            vScale_Type(0) := sharp_flat;
        end case;
      -- Chromatic
      when cCHROMATIC_POS =>
        vScale_Type(1) := cIS_TONAL;
        vScale_Type(0) := sharp_flat;
      when others =>
        vScale_Type(1) := cIS_MODAL;
        vScale_Type(0) := cIS_SHARP;
    end case;
    return vScale_Type;
  end function fGetScaleType;

  -- Given the scale gets the position of active notes with respect to the
  -- palette of colours
  function fGetPalettePos (
    signal Mask : std_logic_vector(11 downto 0))
    return tPalette_Pos_Array is
    variable vPos_array : tPalette_Pos_Array;
    variable vPos : integer range 0 to 12;
  begin  -- function fGetPalettePos
    vPos_array := (others => 0);
    vPos := 0;
    for idx in 0 to 11 loop
      if (Mask(idx) = '1') then
        if (vPos < 12) then
          vPos_array(vPos) := idx;
          vPos := vPos + 1;
        end if;
      end if;
    end loop;  -- idx
    return vPos_array;
  end function fGetPalettePos;

  signal sKEY_reg1, sKEY_reg2 : std_logic_vector(3 downto 0);
  signal sKEY_up : std_logic;
  signal sKEY_down : std_logic;
  signal sPitch_Lock_toggle : std_logic;
  signal sIs_Pitch_Locked : std_logic;
  signal sSharp_Flat_toggle : std_logic;
  signal sIs_Sharp_Flat : std_logic;

  signal sOctave_Start : unsigned(2 downto 0);

  signal sRoot_Note_Val : unsigned(3 downto 0);
  signal sN_Octaves_Sel : std_logic_vector(1 downto 0);
  signal sScale_Mask_Sel : std_logic_vector(3 downto 0);

  signal sN_Octaves : unsigned(2 downto 0) := to_unsigned(2, 3);
  signal sN_Semitones : unsigned(6 downto 0);
  signal sScale_Mask : std_logic_vector(11 downto 0);

begin

  ----------------------
  -- KEY synchronizer
  ----------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sKEY_reg1 <= (others => '1');
      sKEY_reg2 <= (others => '1');
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      sKEY_reg1 <= KEY;
      sKEY_reg2 <= sKEY_reg1;
    end if;
  end process;

  -- push buttons pulses
  sKEY_up <= sKEY_reg2(1) and not(sKEY_reg1(1));
  sKEY_down <= sKEY_reg2(0) and not(sKEY_reg1(0));
  sPitch_Lock_toggle <= sKEY_reg2(2) and not(sKEY_reg1(2));
  sSharp_Flat_toggle <= sKEY_reg2(3) and not(sKEY_reg1(3));

  -----------------------------------------------------------------------------
  -- Starting octave counter (up/down) (KEY1 - KEY0)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sOctave_Start <= cC3_OCTAVE;  -- default: C3
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sKEY_up = '1' and sKEY_down = '0') then
        if (sOctave_Start = cC5_OCTAVE) then
          sOctave_Start <= cC5_OCTAVE;
        else
          sOctave_Start <= sOctave_Start + 1;
        end if;
      elsif (sKEY_up = '0' and sKEY_down = '1') then
        if (sOctave_Start = cC1_OCTAVE) then
          sOctave_Start <= cC1_OCTAVE;
        else
          sOctave_Start <= sOctave_Start - 1;
        end if;
      end if;
    end if;
  end process;

  OCTAVE_START <= sOctave_Start;

  -----------------------------------------------------------------------------
  -- Pitch lock flag (KEY2 toggle)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sIs_Pitch_Locked <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sPitch_Lock_toggle = '1') then
        sIs_Pitch_Locked <= not(sIs_Pitch_Locked);
      end if;
    end if;
  end process;

  PITCH_LOCKED <= sIs_Pitch_Locked;

  -----------------------------------------------------------------------------
  -- Sharp/Flat flag (KEY3 toggle)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sIs_Sharp_Flat <= cIS_SHARP;
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sSharp_Flat_toggle = '1') then
        sIs_Sharp_Flat <= not(sIs_Sharp_Flat);
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- SW mapping
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sRoot_Note_Val <= (others => '0');
      sN_Octaves_Sel <= (others => '0');
      sScale_Mask_Sel <= (others => '0');
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      sRoot_Note_Val <= unsigned(SW(3 downto 0));
      sN_Octaves_Sel <= SW(5 downto 4);
      sScale_Mask_Sel <= SW(9 downto 6);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Tonic: sRoot_Note_Val, clamp a 11
  -----------------------------------------------------------------------------
  ROOT_NOTE <= sRoot_Note_Val when (sRoot_Note_Val <= 11) else to_unsigned(cB_NOTE, 4);

  -----------------------------------------------------------------------------
  -- Number of octaves
  -----------------------------------------------------------------------------
  process (sOctave_Start, sN_Octaves_Sel) is
  begin  -- process
    case to_integer(sOctave_Start) is
      when cC5_OCTAVE_I =>
        sN_Octaves <= to_unsigned(2, 3);
      when cC4_OCTAVE_I =>
        if (sN_Octaves_Sel = "00") then
          sN_Octaves <= to_unsigned(2, 3);
        else
          sN_Octaves <= to_unsigned(3, 3);
        end if;
      when others =>
        if (sN_Octaves_Sel = "00") then
          sN_Octaves <= to_unsigned(2, 3);
        elsif (sN_Octaves_Sel = "01") then
          sN_Octaves <= to_unsigned(3, 3);
        else
          sN_Octaves <= to_unsigned(4, 3);
        end if;
    end case;
  end process;

  N_OCTAVES <= sN_Octaves;

  -----------------------------------------------------------------------------
  -- Total number of semitones = #octaves x 12
  -----------------------------------------------------------------------------
  sN_Semitones <= sN_Octaves * to_unsigned(12, 4);
  N_SEMITONES <= sN_Semitones(5 downto 0);

  -----------------------------------------------------------------------------
  -- Current scale
  -----------------------------------------------------------------------------
  sScale_Mask <= fGetScale(sScale_Mask_Sel);
  SCALE_MASK <= sScale_Mask;

  -- Calculate scale length
  process (sScale_Mask) is
    variable vTmp : integer;
    variable vBit : integer;
  begin  -- process
    vTmp := 0;
    for idx in 0 to 11 loop
      if (sScale_Mask(idx) = '1') then
        vBit := 1;
      else
        vBit := 0;
      end if;
      vTmp := vTmp + vBit;
    end loop;  -- idx
    SCALE_LEN <= to_unsigned(vTmp, 4);
  end process;

  -- Get scale type (Tonal/Modal) (Sharp/Flat)
  SCALE_TYPE <= fGetScaleType(sScale_Mask_Sel, sRoot_Note_Val, sIs_Sharp_Flat);
  -- Get position of active notes w.r.t the palette
  PALETTE_POS <= fGetPalettePos(sScale_Mask);

end architecture;
