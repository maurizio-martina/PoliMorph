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
-- Title      : Digital Direct Synthesis (DDS) mapper
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dds_mapper.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the logic to map the X touch position to the
-- DDS delta phase. Behaviour is inspired by the note indicator: given the
-- current layout the system pre-calculates the distance between notes and
-- possible touches. Then based on the touch it calculates the two closest MIDI
-- notes. If the pitch is locked the closest note is selected otherwise a
-- fractional part is computed and used to derive an intermediate frequency
-- which is finally mapped to the DDS delta phase.
-- NOTE: the HDL has been written such that Quartus can infer M10K blocks to
-- store the pre-calculated values.
-- It has 4 cicles latency.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.mtl2_pkg.all;
use work.notes_pkg.all;

entity dds_mapper is
  port (
    CLK            : in  std_logic;
    RST_n          : in  std_logic;
    ROOT_NOTE      : in  unsigned(3 downto 0);
    N_OCTAVES      : in  unsigned(2 downto 0);
    OCTAVE_START   : in  unsigned(2 downto 0);
    SCALE_LEN      : in  unsigned(3 downto 0);
    N_SEMITONES    : in  unsigned(5 downto 0);
    PALETTE_POS    : in  tPalette_Pos_Array;
    PITCH_LOCKED   : in  std_logic;
    TOUCH_POS_IN   : in  rTouchPosition;
    TOUCH_VALID_IN : in  std_logic;
    MORPH_FACT_OUT : out unsigned(cH_MTL2_NBIT-1 downto 0);
    DDS_PHASE_OUT  : out unsigned(cNBIT_DDS_Phase-1 downto 0);
    DDS_VALID_OUT  : out std_logic
    );
end entity;

architecture rtl of dds_mapper is

  -----------------------------------------------------------------------------
  -- LAYOUT constants, types and functions
  -- Same as note_indicator
  -----------------------------------------------------------------------------

  -- Bar width in pixel
  constant cBAR_W : integer := 2;

  -- Layout parameters type (# of bars, spacing between two bars, margin)
  type rLayout_Params is record
    B : integer;   -- Number of bars per octave
    S : integer;   -- Spacing
    M : integer;   -- Margin
  end record;

  -- Array type to describe the layout parameters for any number of octaves
  -- and any number of bars
  type tParams_Mat is array (0 to cMAX_ACTIVE_OCTAVES_IDX-1, 0 to cMAX_BARS-1)
    of rLayout_Params;

  ---------------------------------------------------------------------------
  -- Calculate all possible layout configurations: margin (M), spacing (S)
  -- and number of bars per octave (B), for 2, 3 and 4 octaves from 1 to 12
  -- bars per octave plus the last bar (closing tonic)
  ---------------------------------------------------------------------------
  function fCalculate_Layout_Conf return tParams_Mat is
    variable configs : tParams_Mat;
    variable b_total : integer;
    variable s_calc  : integer;
    constant W_MAX   : integer := cW;
    constant S_MIN   : integer := 13;
    constant S_MAX   : integer := 270;
    constant M_MIN   : integer := 10;
  begin
    for oct in 2 to 4 loop
      for n in 1 to cMAX_BARS loop
        b_total := (n * oct) + 1;
        -- 1 Calculate the spacing to fill the screen with minimum margin
        s_calc := (W_MAX - (2 * M_MIN) - (b_total * cBAR_W)) / (b_total - 1);

        -- 2. verify that spacing is between min and max
        if s_calc < S_MIN then
          s_calc := S_MIN;
        elsif s_calc > S_MAX then
          s_calc := S_MAX;
        end if;

        configs(oct-2, n-1).B := n;
        configs(oct-2, n-1).S := s_calc;

        -- 3. Calculate the real margin (symmetric)
        configs(oct-2, n-1).M :=
          (W_MAX - ((b_total * cBAR_W) + (b_total - 1) * s_calc)) / 2;
      end loop;
    end loop;
    return configs;
  end function;

  -- Layout parameters array (elaboration-time constant)
  constant cLAYOUT_CONF : tParams_Mat := fCalculate_Layout_Conf;

  ---------------------------------------------------------------------------
  -- Distance-factor resolution
  ---------------------------------------------------------------------------
  constant cDIST_FACT_NBIT : integer := 9;
  constant cDIST_FACT05    : unsigned(cDIST_FACT_NBIT-1 downto 0) :=
    (cDIST_FACT_NBIT-1 => '1', others => '0');

  ---------------------------------------------------------------------------
  -- Internal record / 2-D types used ONLY inside fTHpos_Rom_Init.
  -- They are NOT used for any signal or constant that must map to M10K.
  ---------------------------------------------------------------------------
  type rTHpos_Rom_Elem is record
    Dist_fact : unsigned(cDIST_FACT_NBIT-1 downto 0);
    Bar_idx   : integer range 0 to cMAX_BARS-1;
    Oct_idx   : integer range 0 to cMAX_ACTIVE_OCTAVES_IDX+2;
  end record rTHpos_Rom_Elem;

  type tTHpos_Rom_Line is
    array (0 to cMAX_ACTIVE_OCTAVES_IDX-1, 0 to cMAX_BARS-1)
    of rTHpos_Rom_Elem;

  type tTHpos_Rom is array (0 to cW-1) of tTHpos_Rom_Line;

  -- Build the structured ROM (used only as input to the flat packer below)
  function fTHpos_Rom_Init return tTHpos_Rom is
    variable vRom : tTHpos_Rom;
    variable vBar : integer;
    variable vXref : integer;
  begin
    for oct in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
      for nbars in 0 to cMAX_BARS-1 loop
        vBar  := 0;
        vXref := 0;
        for idx in 0 to cW-1 loop
          -- lower than left margin
          if (idx < cLAYOUT_CONF(oct, nbars).M) then
            vRom(idx)(oct, nbars).Dist_fact := (others => '0');
            vRom(idx)(oct, nbars).Bar_idx   := 0;
            vRom(idx)(oct, nbars).Oct_idx   := 0;
          -- greater than right margin
          elsif (idx >= (cW - cLAYOUT_CONF(oct, nbars).M)) then
            vRom(idx)(oct, nbars).Dist_fact := (others => '0');
            vRom(idx)(oct, nbars).Bar_idx   := vBar rem cLAYOUT_CONF(oct, nbars).B;
            vRom(idx)(oct, nbars).Oct_idx   := vBar  /  cLAYOUT_CONF(oct, nbars).B;
          else
            -- exactly on a bar: touch distance to note is 0
            if (idx < (cLAYOUT_CONF(oct, nbars).M
                       + vBar*(cBAR_W + cLAYOUT_CONF(oct, nbars).S)
                       + cBAR_W)) then
              vRom(idx)(oct, nbars).Dist_fact := (others => '0');
              vRom(idx)(oct, nbars).Bar_idx   := vBar rem cLAYOUT_CONF(oct, nbars).B;
              vRom(idx)(oct, nbars).Oct_idx   := vBar  /  cLAYOUT_CONF(oct, nbars).B;
            -- between two bars: touch distance to note is normalized as
            -- (touch-vXref)/S but keeping cDIST_FACT_NBIT fractional bits
            elsif (idx < (cLAYOUT_CONF(oct, nbars).M
                          + vBar*(cBAR_W + cLAYOUT_CONF(oct, nbars).S)
                          + cBAR_W + cLAYOUT_CONF(oct, nbars).S)) then
              vXref := cLAYOUT_CONF(oct, nbars).M
                       + vBar*(cBAR_W + cLAYOUT_CONF(oct, nbars).S) + cBAR_W;
              vRom(idx)(oct, nbars).Dist_fact :=
                to_unsigned(
                  integer(round(
                    real(idx - vXref) / real(cLAYOUT_CONF(oct, nbars).S)
                    * real(2**cDIST_FACT_NBIT))),
                  cDIST_FACT_NBIT);
              vRom(idx)(oct, nbars).Bar_idx := vBar rem cLAYOUT_CONF(oct, nbars).B;
              vRom(idx)(oct, nbars).Oct_idx := vBar  /  cLAYOUT_CONF(oct, nbars).B;
              if (idx = (cLAYOUT_CONF(oct, nbars).M
                         + vBar*(cBAR_W + cLAYOUT_CONF(oct, nbars).S)
                         + cBAR_W + cLAYOUT_CONF(oct, nbars).S - 1)) then
                vBar := vBar + 1;
              end if;
            end if;
          end if;
        end loop;  -- idx
      end loop;  -- nbars
    end loop;  -- oct
    return vRom;
  end function fTHpos_Rom_Init;

  ---------------------------------------------------------------------------
  -- Flat THpos_ROM to make M10K-compatible
  -- Each ROM word packs ALL combinations of (oct_idx, bar_idx) into a
  -- single std_logic_vector so that Quartus sees a plain 1-D array of
  -- std_logic_vectors and can map it to M10K block(s).
  --
  -- Field layout inside one word:
  --   [cDIST_FACT_NBIT-1 : 0]                    -> Dist_fact
  --   [cDIST_FACT_NBIT + cBAR_IDX_NBIT - 1
  --    : cDIST_FACT_NBIT]                         -> Bar_idx
  --   [cELEM_W-1
  --    : cDIST_FACT_NBIT + cBAR_IDX_NBIT]         -> Oct_idx
  --
  -- Element offset inside the word for (oct, nb):
  --   base = (oct * cMAX_BARS + nb) * cELEM_W
  ---------------------------------------------------------------------------
  constant cBAR_IDX_NBIT : integer := 4;
  constant cOCT_IDX_NBIT : integer := 3;
  constant cELEM_W       : integer := cDIST_FACT_NBIT + cBAR_IDX_NBIT + cOCT_IDX_NBIT;
  constant cROM_WORD_W   : integer := cELEM_W * cMAX_ACTIVE_OCTAVES_IDX * cMAX_BARS;

  -- 2-D array of std_logic_vectors: the ONLY shape Quartus can infer as M10K ROM
  type tTHpos_Rom_flat is array (0 to cW-1)
    of std_logic_vector(cROM_WORD_W-1 downto 0);

  -- Pack the structured ROM into the flat representation at elaboration time
  function fTHpos_Rom_Init_flat return tTHpos_Rom_flat is
    variable vSrc  : tTHpos_Rom       := fTHpos_Rom_Init;
    variable vFlat : tTHpos_Rom_flat;
    variable base  : integer;
  begin
    for idx in 0 to cW-1 loop
      vFlat(idx) := (others => '0');
      for oct in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
        for nb in 0 to cMAX_BARS-1 loop
          base := (oct * cMAX_BARS + nb) * cELEM_W;
          -- Dist_fact field
          vFlat(idx)(base + cDIST_FACT_NBIT - 1 downto base) :=
            std_logic_vector(vSrc(idx)(oct, nb).Dist_fact);
          -- Bar_idx field
          vFlat(idx)(base + cDIST_FACT_NBIT + cBAR_IDX_NBIT - 1
                     downto base + cDIST_FACT_NBIT) :=
            std_logic_vector(to_unsigned(vSrc(idx)(oct, nb).Bar_idx, cBAR_IDX_NBIT));
          -- Oct_idx field
          vFlat(idx)(base + cELEM_W - 1
                     downto base + cDIST_FACT_NBIT + cBAR_IDX_NBIT) :=
            std_logic_vector(to_unsigned(vSrc(idx)(oct, nb).Oct_idx, cOCT_IDX_NBIT));
        end loop;
      end loop;
    end loop;
    return vFlat;
  end function fTHpos_Rom_Init_flat;

  -- the ROM
  signal sTHpos_Rom : tTHpos_Rom_flat := fTHpos_Rom_Init_flat;

  attribute ramstyle : string;
  attribute ramstyle of sTHpos_Rom : signal is "M10K, no_rw_check";

  -----------------------------------------------------------------------------
  -- DDS constants, types and functions
  -----------------------------------------------------------------------------

  constant cFS              : integer := 48000;
  constant cNBIT_Phase      : integer := cNBIT_DDS_Phase;
  constant cMIDI_NBIT       : integer := 8;
  constant cNBIT_K_DDS_INT  : integer := 9;
  constant cNBIT_K_DDS_FRAC : integer := 9;
  constant cNBIT_K_DDS      : integer := cNBIT_K_DDS_INT + cNBIT_K_DDS_FRAC;
  constant cK_DDS_I         : integer :=
    integer(round(real(2**cNBIT_Phase) / real(cFS) * real(2**cNBIT_K_DDS_FRAC)));
  constant cK_DDS           : unsigned(cNBIT_K_DDS-1 downto 0) :=
    to_unsigned(cK_DDS_I, cNBIT_K_DDS);

  constant cMIDI_NELEMS            : integer := 128;
  constant cNBIT_FREQ_TABLE_I_INT  : integer := 14;
  constant cNBIT_FREQ_TABLE_I_FRAC : integer := 4;
  constant cNBIT_FREQ_TABLE_I      : integer :=
    cNBIT_FREQ_TABLE_I_INT + cNBIT_FREQ_TABLE_I_FRAC;
  constant cFRAC_NELEMS          : integer := 2**(cDIST_FACT_NBIT+4);
  constant cNBIT_FREQ_TABLE_F_INT  : integer := 2;
  constant cNBIT_FREQ_TABLE_F_FRAC : integer := 12;
  constant cNBIT_FREQ_TABLE_F      : integer :=
    cNBIT_FREQ_TABLE_F_INT + cNBIT_FREQ_TABLE_F_FRAC;

  -- DDS frequency array types (integer and fractional)
  type tDDS_freq_table_i is array (0 to cMIDI_NELEMS-1)
    of unsigned(cNBIT_FREQ_TABLE_I-1 downto 0);
  type tDDS_freq_table_f is array (0 to cFRAC_NELEMS-1)
    of unsigned(cNBIT_FREQ_TABLE_F-1 downto 0);

  -- Frequency integer part: F_I = round(440 * 2^[(idx-69)/12] * 2^FRAC_BITS)
  function fInit_DDS_freq_table_i return tDDS_freq_table_i is
    variable mat : tDDS_freq_table_i;
    variable fi  : integer;
  begin
    for idx in 0 to cMIDI_NELEMS-1 loop
      fi := integer(round(
              440.0 * (2.00**(real(idx-69)/12.0)) * real(2**cNBIT_FREQ_TABLE_I_FRAC)));
      mat(idx) := to_unsigned(fi, cNBIT_FREQ_TABLE_I);
    end loop;
    return mat;
  end function fInit_DDS_freq_table_i;

  -- Frequency fractional part: F_F = round(2^[idx / (512*12)] * 2^FRAC_BITS)
  function fInit_DDS_freq_table_f return tDDS_freq_table_f is
    variable mat : tDDS_freq_table_f;
    variable ff  : integer;
  begin
    for idx in 0 to cFRAC_NELEMS-1 loop
      ff := integer(round(
              (2.00**(real(idx) / real(2**cDIST_FACT_NBIT) / 12.0))
              * real(2**cNBIT_FREQ_TABLE_F_FRAC)));
      mat(idx) := to_unsigned(ff, cNBIT_FREQ_TABLE_F);
    end loop;
    return mat;
  end function fInit_DDS_freq_table_f;

  constant cDDS_freq_table_i : tDDS_freq_table_i := fInit_DDS_freq_table_i;
  constant cDDS_freq_table_f : tDDS_freq_table_f := fInit_DDS_freq_table_f;

  attribute ramstyle of cDDS_freq_table_i : constant is "M10K";
  attribute ramstyle of cDDS_freq_table_f : constant is "M10K";

  ---------------------------------------------------------------------------
  -- fDDS_freq_value
  -- F = F_I(noteA) * F_F( (noteB-noteA) * t )
  -- F_I: 14.4 fixed-point   F_F: 1.12 fixed-point   result: 14.4
  ---------------------------------------------------------------------------
  function fDDS_freq_value (
    constant noteA : integer range 0 to 127;
    constant noteB : integer range 0 to 127;
    constant t     : unsigned(cDIST_FACT_NBIT-1 downto 0))
    return unsigned is
    variable vFreq_int   : unsigned(cNBIT_FREQ_TABLE_I-1 downto 0);
    variable tmp         : unsigned(cDIST_FACT_NBIT+4-1 downto 0);
    variable vFreq_fract : unsigned(cNBIT_FREQ_TABLE_F-1 downto 0);
    variable prod        : unsigned(cNBIT_FREQ_TABLE_I+cNBIT_FREQ_TABLE_F-1 downto 0);
    variable vFreqR      : unsigned(cNBIT_FREQ_TABLE_I-1 downto 0);
  begin
    vFreq_int   := cDDS_freq_table_i(noteA);
    tmp         := to_unsigned(noteB - noteA, 4) * t;
    vFreq_fract := cDDS_freq_table_f(to_integer(tmp));
    prod        := vFreq_int * vFreq_fract;
    vFreqR      := prod(cNBIT_FREQ_TABLE_I + cNBIT_FREQ_TABLE_F_FRAC - 1
                        downto cNBIT_FREQ_TABLE_F_FRAC);
    return vFreqR;
  end function fDDS_freq_value;

  -----------------------------------------------------------------------------
  -- Signals
  -----------------------------------------------------------------------------

  -- Stage 1: one flat ROM word registered on the rising edge
  signal s1_touch_valid    : std_logic;
  signal s1_touch_pos_y    : unsigned(cH_MTL2_NBIT-1 downto 0);
  signal s1_THpos_Rom_Word : std_logic_vector(cROM_WORD_W-1 downto 0);

  -- Stage 2: fields unpacked and muxed from the flat word
  signal s2_touch_valid : std_logic;
  signal s2_Dist_fact   : unsigned(cDIST_FACT_NBIT-1 downto 0);
  signal s2_Bar_idx     : integer range 0 to cMAX_BARS-1;
  signal s2_Oct_idx     : integer range 0 to cMAX_ACTIVE_OCTAVES_IDX+2;
  signal s2_touch_pos_y : unsigned(cH_MTL2_NBIT-1 downto 0);

  signal sDDS_freq : unsigned(cNBIT_FREQ_TABLE_I-1 downto 0);

  -- Stage 3
  signal s3_touch_valid : std_logic;
  signal s3_dds_freq    : unsigned(cNBIT_FREQ_TABLE_I-1 downto 0);
  signal s3_touch_pos_y : unsigned(cH_MTL2_NBIT-1 downto 0);

  -- Stage 4
  signal s4_touch_valid : std_logic;
  signal s4_dds_phase   : unsigned(cNBIT_Phase-1 downto 0);
  signal s4_touch_pos_y : unsigned(cH_MTL2_NBIT-1 downto 0);

begin

  -----------------------------------------------------------------------------
  --  Stage 1 - Synchronous reading from flat ROM
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin
    if RST_n = '0' then
      s1_touch_valid    <= '0';
      s1_touch_pos_y    <= (others => '0');
      s1_THpos_Rom_Word <= (others => '0');
    elsif rising_edge(CLK) then
      s1_touch_valid    <= TOUCH_VALID_IN;
      s1_touch_pos_y    <= TOUCH_POS_IN.y;
      -- Synchronous reading to infer M10K
      s1_THpos_Rom_Word <= sTHpos_Rom(to_integer(TOUCH_POS_IN.x));
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Stage 2 - unpack the ROM line and mux depending on N_OCTAVES/SCALE_LEN
  -- =========================================================
  process (CLK, RST_n) is
    variable vLine   : tTHpos_Rom_Line;  -- local buffer for unpacking
    variable base    : integer;
    variable oct_sel : integer;
    variable nb_sel  : integer;
  begin
    if RST_n = '0' then
      s2_touch_valid <= '0';
      s2_touch_pos_y <= (others => '0');
      s2_Dist_fact   <= (others => '0');
      s2_Bar_idx     <= 0;
      s2_Oct_idx     <= 0;
    elsif rising_edge(CLK) then
      s2_touch_valid <= s1_touch_valid;
      s2_touch_pos_y <= s1_touch_pos_y;

      -- -------------------------------------------------------
      -- Unpack the word
      -- -------------------------------------------------------
      for oct in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
        for nb in 0 to cMAX_BARS-1 loop
          base := (oct * cMAX_BARS + nb) * cELEM_W;
          vLine(oct, nb).Dist_fact :=
            unsigned(s1_THpos_Rom_Word(base + cDIST_FACT_NBIT - 1 downto base));
          vLine(oct, nb).Bar_idx :=
            to_integer(unsigned(
              s1_THpos_Rom_Word(
                base + cDIST_FACT_NBIT + cBAR_IDX_NBIT - 1
                downto base + cDIST_FACT_NBIT)));
          vLine(oct, nb).Oct_idx :=
            to_integer(unsigned(
              s1_THpos_Rom_Word(
                base + cELEM_W - 1
                downto base + cDIST_FACT_NBIT + cBAR_IDX_NBIT)));
        end loop;
      end loop;

      -- -------------------------------------------------------
      -- Mux: select the correct portion depending on parameters
      -- -------------------------------------------------------
      if (s1_touch_valid = '1') then
        oct_sel := to_integer(N_OCTAVES) - 2;
        nb_sel  := to_integer(SCALE_LEN) - 1;
        s2_Dist_fact <= vLine(oct_sel, nb_sel).Dist_fact;
        s2_Bar_idx   <= vLine(oct_sel, nb_sel).Bar_idx;
        s2_Oct_idx   <= vLine(oct_sel, nb_sel).Oct_idx;
      else
        s2_Dist_fact <= (others => '0');
        s2_Bar_idx   <= 0;
        s2_Oct_idx   <= 0;
      end if;
    end if;
  end process;

  -- calculate DDS frequency
  process (s2_Dist_fact, s2_Bar_idx, s2_Oct_idx,
           ROOT_NOTE, PALETTE_POS, PITCH_LOCKED, OCTAVE_START, SCALE_LEN) is
    variable vDist_fact  : unsigned(cDIST_FACT_NBIT-1 downto 0);
    variable vBar_idx   : integer range 0 to cMAX_BARS-1;
    variable vOct_idx   : integer;
    -- A
    variable vBar_idxA   : integer range 0 to cMAX_BARS-1;
    variable vNote_idxA  : integer;
    variable vOct_idxA   : integer;
    variable vMidi_noteA : integer range 0 to 127;
    -- B
    variable vBar_idxB   : integer range 0 to cMAX_BARS-1;
    variable vNote_idxB  : integer;
    variable vOct_idxB   : integer;
    variable vMidi_noteB : integer range 0 to 127;
  begin
    -- Prepare distance factor, bar index and octave index
    if (PITCH_LOCKED = '1') then
      vDist_fact := (others => '0');
      if (s2_Dist_fact > cDIST_FACT05) then
        if ((s2_Bar_idx + 1) > (to_integer(SCALE_LEN) - 1)) then
          vBar_idx := 0;
          vOct_idx := s2_Oct_idx + 1;
        else
          vBar_idx := s2_Bar_idx + 1;
          vOct_idx := s2_Oct_idx;
        end if;
      else
        vBar_idx := s2_Bar_idx;
        vOct_idx := s2_Oct_idx;
      end if;
    else
      vDist_fact := s2_Dist_fact;
      vBar_idx  := s2_Bar_idx;
      vOct_idx  := s2_Oct_idx;
    end if;

    -- Note A
    vBar_idxA := vBar_idx;
    vOct_idxA := vOct_idx;
    vNote_idxA := to_integer(ROOT_NOTE) + PALETTE_POS(vBar_idxA);
    if (vNote_idxA > 11) then
      vNote_idxA := vNote_idxA - 12;
      vOct_idxA  := vOct_idxA + 1;
    end if;
    vMidi_noteA := (to_integer(OCTAVE_START) + vOct_idxA + 1) * 12 + vNote_idxA;

    -- Note B
    if ((vBar_idx + 1) > (to_integer(SCALE_LEN) - 1)) then
      vBar_idxB := 0;
      vOct_idxB := vOct_idx + 1;
    else
      vBar_idxB := vBar_idx + 1;
      vOct_idxB := vOct_idx;
    end if;
    vNote_idxB := to_integer(ROOT_NOTE) + PALETTE_POS(vBar_idxB);
    if (vNote_idxB > 11) then
      vNote_idxB := vNote_idxB - 12;
      vOct_idxB  := vOct_idxB + 1;
    end if;
    vMidi_noteB := (to_integer(OCTAVE_START) + vOct_idxB + 1) * 12 + vNote_idxB;

    sDDS_freq <= fDDS_freq_value(vMidi_noteA, vMidi_noteB, vDist_fact);
  end process;

  -----------------------------------------------------------------------------
  --  Stage 3: register after the logic to calculate the DDS frequency
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin
    if RST_n = '0' then
      s3_touch_valid <= '0';
      s3_touch_pos_y <= (others => '0');
      s3_dds_freq    <= (others => '0');
    elsif rising_edge(CLK) then
      s3_touch_valid <= s2_touch_valid;
      s3_touch_pos_y <= s2_touch_pos_y;
      if (s2_touch_valid = '1') then
        s3_dds_freq <= sDDS_freq;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Stage 4 - DDS phase computation:
  --  freq * K_DDS  where K_DDS = 2^Nb / fs
  --  NOTE: since freq -> 14.4 and K_DDS -> 9.9 the product is 18x18=36 (fits
  --  in a DSP); keep 24 bits
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
    variable tmp : unsigned(cNBIT_FREQ_TABLE_I + cNBIT_K_DDS - 1 downto 0);
  begin
    if RST_n = '0' then
      s4_touch_valid <= '0';
      s4_touch_pos_y <= (others => '0');
      s4_dds_phase   <= (others => '0');
    elsif rising_edge(CLK) then
      s4_touch_valid <= s3_touch_valid;
      s4_touch_pos_y <= s3_touch_pos_y;
      if (s3_touch_valid = '1') then
        tmp          := s3_dds_freq * cK_DDS;
        s4_dds_phase <= resize(
          tmp(cNBIT_FREQ_TABLE_I + cNBIT_K_DDS - 1
              downto cNBIT_FREQ_TABLE_I_FRAC + cNBIT_K_DDS_FRAC),
          cNBIT_Phase);
      end if;
    end if;
  end process;

  MORPH_FACT_OUT <= s4_touch_pos_y;
  DDS_VALID_OUT  <= s4_touch_valid;
  DDS_PHASE_OUT  <= s4_dds_phase;

end architecture;
