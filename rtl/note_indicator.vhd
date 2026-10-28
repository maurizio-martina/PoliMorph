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
-- Title      : Note indicator
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : note_indicator.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of the circuit that
-- draws notes as coloured vertical bars on the LCD To simplify the circuit
-- configurations are precalculated and stored in a ROM. The idea stems from
-- observing that the MTL2 has W=800, the number of octaves ranges from 2 to 4,
-- with 1 to 12 semitones. Each note occupies 2 pixles, thus the spacing
-- depends on the number of octaves and on the selected scale, plus some unused
-- pixels on the left and right. Then, given that the MTL2 has H=480, at y=450
-- the names of the notes are shown. The circuit has 3 cycle pipeline.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;
use work.notes_pkg.all;

entity note_indicator is
  port (
    CLK          : in  std_logic;
    RST_n        : in  std_logic;
    ROOT_NOTE    : in  unsigned(3 downto 0);
    N_OCTAVES    : in  unsigned(2 downto 0);
    OCTAVE_START : in  unsigned(2 downto 0);
    SCALE_MASK   : in  std_logic_vector(11 downto 0);
    SCALE_LEN    : in  unsigned(3 downto 0);
    SCALE_TYPE   : in  std_logic_vector(1 downto 0);
    N_SEMITONES  : in  unsigned(5 downto 0);
    PALETTE_POS  : in  tPalette_Pos_Array;
    -- Current pixel coordinates from display/VGA controller
    HPOS         : in  unsigned(cW_MTL2_NBIT-1 downto 0);
    VPOS         : in  unsigned(cH_MTL2_NBIT-1 downto 0);
    DE_IN        : in  std_logic;
    -- Output color layers
    R_OUT        : out unsigned(7 downto 0);
    G_OUT        : out unsigned(7 downto 0);
    B_OUT        : out unsigned(7 downto 0);
    DE_OUT       : out std_logic
    );
end entity;

architecture rtl of note_indicator is

  constant cBAR_W : integer := 2;

  type rLayout_Params is record
    B : integer;                        -- Number of bars per octave
    S : integer;                        -- Spacing
    M : integer;                        -- Margin
  end record;

  type tParams_Mat is array (0 to cMAX_ACTIVE_OCTAVES_IDX-1, 0 to cMAX_BARS-1) of rLayout_Params;

  -----------------------------------------------------------------------------
  -- Calculate all possible layout configurations: margin (M), spacing (S) and
  -- number of bars per octave (B), for 2, 3 and 4 octaves from 1 to 12 bars
  -- per octave plus the last bar (closing tonic)
  -----------------------------------------------------------------------------
  function fCalculate_Layout_Conf return tParams_Mat is
    variable configs : tParams_Mat;
    variable b_total : integer;
    variable s_calc  : integer;
    constant W_MAX   : integer := cW;
    constant S_MIN   : integer := 13;   -- minimum spacing between vertical bars to have readable fonts
    constant S_MAX   : integer := 270;  -- maximum spacing between vertical
                                        -- bars to have not-too-distant bars
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
        configs(oct-2, n-1).M := (W_MAX - ((b_total * cBAR_W) + (b_total - 1) * s_calc)) / 2;
      end loop;
    end loop;
    return configs;
  end function;

  constant cLAYOUT_CONF : tParams_Mat := fCalculate_Layout_Conf;

  type rHpos_Rom_Elem is record
    Is_bar  : std_logic;
    Bar_idx : integer range 0 to cMAX_BARS-1;
  end record rHpos_Rom_Elem;

  type tHpos_Rom_Line is array (0 to cMAX_ACTIVE_OCTAVES_IDX-1, 0 to cMAX_BARS-1) of rHpos_Rom_Elem;

  type tHpos_Rom is array (0 to cW-1) of tHpos_Rom_Line;

  -----------------------------------------------------------------------------
  -- Prepare a ROM with the bar layout:
  -- the ROM has cW rows, each row contains the information to show the corresponding
  -- pixel on the display independently of the Y coordinate. The information is
  -- precalculated for 2, 3 and 4 octaves for 1 to 12 bars per octave.
  -- The algorithm implemented in "fCalculate_Layout_Conf" permits to have a
  -- good balance in term of margin (M), spacing between bars (S) and number of
  -- bars per octave (B).
  -- XXXX...XXX||XXXX...XXXX||...||XXX...XXXX
  -- XXXX...XXX||XXXX...XXXX||...||XXX...XXXX
  -- XXXX...XXX||XXXX...XXXX||...||XXX...XXXX
  -- < margin > 0< spacing > 1... 2< margin >
  -----------------------------------------------------------------------------
  function fHpos_Rom_Init return tHpos_Rom is
    variable vRom : tHpos_Rom;
    variable vBar : integer;
  begin  -- function fHpos_Rom_Init
    for oct in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
      for nbars in 0 to cMAX_BARS-1 loop
        vBar := 0;
        for idx in 0 to cW-1 loop
          -- check margin bounds
          if ((idx < cLAYOUT_CONF(oct, nbars).M) or (idx >= (cW-cLAYOUT_CONF(oct, nbars).M))) then
            vRom(idx)(oct, nbars).Is_bar  := '0';
            vRom(idx)(oct, nbars).Bar_idx := 0;
          else
            -- bar
            if (idx < (cLAYOUT_CONF(oct, nbars).M + vBar*(cBAR_W+cLAYOUT_CONF(oct, nbars).S)+cBAR_W)) then
              vRom(idx)(oct, nbars).Is_bar  := '1';
              vRom(idx)(oct, nbars).Bar_idx := vBar rem cLAYOUT_CONF(oct, nbars).B;
            -- spacing
            elsif (idx < (cLAYOUT_CONF(oct, nbars).M + vBar*(cBAR_W+cLAYOUT_CONF(oct, nbars).S)+cBAR_W+cLAYOUT_CONF(oct, nbars).S)) then
              vRom(idx)(oct, nbars).Is_bar  := '0';
              vRom(idx)(oct, nbars).Bar_idx := vBar rem cLAYOUT_CONF(oct, nbars).B;
              if (idx = (cLAYOUT_CONF(oct, nbars).M + vBar*(cBAR_W+cLAYOUT_CONF(oct, nbars).S)+cBAR_W+cLAYOUT_CONF(oct, nbars).S-1)) then
                vBar := vBar + 1;
              end if;
            end if;
          end if;
        end loop;  -- idx
      end loop;  -- nbars
    end loop;  -- oct
    return vRom;
  end function fHpos_Rom_Init;

  constant cHpos_Rom : tHpos_Rom := fHpos_Rom_Init;

  signal sM : integer;
  signal sS : integer;
  signal sW : integer;
  signal sB : integer;

  signal s1_de            : std_logic;
  signal s1_Hpos_Rom_Line : tHpos_Rom_Line;
  signal s1_Is_font       : std_logic;
  signal s1_Is_backg      : std_logic;
  signal s1_Is_SF         : std_logic;
  signal s1_Font_row      : integer range 0 to 6;
  signal s1_Font_col      : integer range 0 to 5;
  signal s1_SF_row        : integer range 0 to 6;
  signal s1_SF_col        : integer range 0 to 2;

  signal s2_de       : std_logic;
  signal s2_Is_bar   : std_logic;
  signal s2_Bar_idx  : integer range 0 to 11;
  signal s2_Is_font  : std_logic;
  signal s2_Is_backg : std_logic;
  signal s2_Is_SF    : std_logic;
  signal s2_Font_row : integer range 0 to 6;
  signal s2_Font_col : integer range 0 to 5;
  signal s2_SF_row   : integer range 0 to 6;
  signal s2_SF_col   : integer range 0 to 2;
  signal s2_Font_cnt : integer range 0 to 15;

  signal s23_R_i : unsigned(7 downto 0);
  signal s23_G_i : unsigned(7 downto 0);
  signal s23_B_i : unsigned(7 downto 0);

  signal s3_de : std_logic;
  signal s3_R_reg : unsigned(7 downto 0);
  signal s3_G_reg : unsigned(7 downto 0);
  signal s3_B_reg : unsigned(7 downto 0);

begin

  -----------------------------------------------------------------------------
  -- Prepare margin (M), spacing (S) and number of bars per octave (B)
  -- based on input paramters
  -----------------------------------------------------------------------------
  process (N_OCTAVES, SCALE_LEN) is
    variable idx1 : integer;
    variable idx2 : integer;
  begin  -- process
    if (to_integer(N_OCTAVES) < 2) then
      idx1 := 0;
    else
      idx1 := to_integer(N_OCTAVES)-2;
    end if;
    if (to_integer(SCALE_LEN) < 1) then
      idx2 := 0;
    else
      idx2 := to_integer(SCALE_LEN)-1;
    end if;
    sM <= cLAYOUT_CONF(idx1, idx2).M;
    sS <= cLAYOUT_CONF(idx1, idx2).S;
    sB <= cLAYOUT_CONF(idx1, idx2).B;
  end process;

  sW <= 2;

  -----------------------------------------------------------------------------
  -- Pipeline stage 1 (s1)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
    variable vHTHRA : integer range 0 to cW+cW/2-1;
    variable vHTHRB : integer range 0 to cW+cW/2-1;
    variable vHTHRC : integer range 0 to cW+cW/2-1;
  begin
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s1_de <= '0';
      for idx in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
        for jdx in 0 to cMAX_BARS-1 loop
          s1_Hpos_Rom_Line(idx, jdx).Is_bar  <= '0';
          s1_Hpos_Rom_Line(idx, jdx).Bar_idx <= 0;
        end loop;  -- jdx
      end loop;  -- idx
      s1_Is_backg <= '0';
      s1_Is_font  <= '0';
      s1_Is_SF    <= '0';
      s1_Font_row <= 0;
      s1_Font_col <= 0;
      s1_SF_row   <= 0;
      s1_SF_col   <= 0;
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s1_de <= DE_IN;
      if (DE_IN = '1') then
        -----------------------------------------------------------------------
        -- row-wise part:
        -- get the line from ROM @HPOS to manage bars
        -----------------------------------------------------------------------
        s1_Hpos_Rom_Line <= cHpos_Rom(to_integer(HPOS));
        -----------------------------------------------------------------------
        -- column-wise part:
        -- if vertical position reached cVTHR1 (450) start managing note names
        -----------------------------------------------------------------------
        if (to_integer(VPOS) >= cVTHR1) then
          -- leave some space between bars and note names (13 pixels forced as Is background)
          if (to_integer(VPOS) < cVTHR2) then
            s1_Is_backg <= '1';
            s1_Is_font  <= '0';
            s1_Is_SF    <= '0';
            s1_Font_row <= 0;
            s1_Font_col <= 0;
            s1_SF_row   <= 0;
            s1_SF_col   <= 0;
          -- start managing note names with font ROMs
          elsif (to_integer(VPOS) < cVTHR3) then
            -- calculate font row as vertical position minus cVTHR2 (150+13)
            s1_Font_row <= to_integer(VPOS) - cVTHR2;
            s1_SF_row   <= to_integer(VPOS) - cVTHR2;
            -- set font position across the bar: 2 px left, 2 px bar, 2 px right:
            -- calculate font column as horizontal position minus vHTHRA:
            -- (M-2) + (W+S) x counter
            -- the counter is incremented when HPOS reaches vHTHRB = (M+W+2) + (W+S) x counter
            if ((to_integer(HPOS) >= vHTHRA) and (to_integer(HPOS) < vHTHRB)) then
              s1_Font_col <= to_integer(HPOS) - vHTHRA;
              s1_SF_col   <= 0;
              s1_Is_backg <= '0';
              s1_Is_font  <= '1';
              s1_Is_SF    <= '0';
            elsif ((to_integer(HPOS) >= vHTHRB) and (to_integer(HPOS) < vHTHRC)) then
              s1_Font_col <= 0;
              s1_SF_col   <= to_integer(HPOS) - vHTHRB;
              s1_Is_backg <= '0';
              s1_Is_font  <= '1';
              s1_Is_SF    <= '1';
            elsif (to_integer(HPOS) = vHTHRC) then
              s1_Font_col <= 0;
              s1_SF_col   <= 0;
              s1_Is_backg <= '1';
              s1_Is_font  <= '0';
              s1_Is_SF    <= '0';
              vHTHRA      := vHTHRA + sW+sS;
              vHTHRB      := vHTHRB + sW+sS;
              vHTHRC      := vHTHRC + sW+sS;
            end if;
          else
            s1_Is_backg <= '1';
            s1_Is_font  <= '0';
            s1_Is_SF    <= '0';
            s1_Font_row <= 0;
            s1_Font_col <= 0;
            s1_SF_row   <= 0;
            s1_SF_col   <= 0;
            vHTHRA      := sM-2;
            vHTHRB      := sM+sW+2;
            VHTHRC      := sM+sW+2+3;
          end if;
        else
          s1_Is_backg <= '0';
          s1_Is_font  <= '0';
          s1_Is_SF    <= '0';
          s1_Font_row <= 0;
          s1_Font_col <= 0;
          s1_SF_row   <= 0;
          s1_SF_col   <= 0;
          vHTHRA      := sM-2;
          vHTHRB      := sM+sW+2;
          VHTHRC      := sM+sW+2+3;
        end if;
      else
        for idx in 0 to cMAX_ACTIVE_OCTAVES_IDX-1 loop
          for jdx in 0 to cMAX_BARS-1 loop
            s1_Hpos_Rom_Line(idx, jdx).Is_bar  <= '0';
            s1_Hpos_Rom_Line(idx, jdx).Bar_idx <= 0;
          end loop;  -- jdx
        end loop;  -- idx
        s1_Is_backg <= '0';
        s1_Is_font  <= '0';
        s1_Is_SF    <= '0';
        s1_Font_row <= 0;
        s1_Font_col <= 0;
        s1_SF_row   <= 0;
        s1_SF_col   <= 0;
        vHTHRA      := sM-2;
        vHTHRB      := sM+sW+2;
        VHTHRC      := sM+sW+2+3;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Pipeline stage 2 (s2)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s2_de       <= '0';
      s2_Is_bar   <= '0';
      s2_Bar_idx  <= 0;
      s2_Is_backg <= '0';
      s2_Is_font  <= '0';
      s2_Is_SF    <= '0';
      s2_Font_row <= 0;
      s2_Font_col <= 0;
      s2_SF_row   <= 0;
      s2_SF_col   <= 0;
      s2_Font_cnt <= 0;
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s2_de <= s1_de;
      if (s1_de = '1') then
        -----------------------------------------------------------------------
        -- row-wise part:
        -- multiplex the ROM line depending on the number of octaves and the length of the scale
        -----------------------------------------------------------------------
        s2_Is_bar   <= s1_Hpos_Rom_Line(to_integer(N_OCTAVES)-2, to_integer(SCALE_LEN)-1).Is_bar;
        s2_Bar_idx  <= s1_Hpos_Rom_Line(to_integer(N_OCTAVES)-2, to_integer(SCALE_LEN)-1).Bar_idx;
        -----------------------------------------------------------------------
        -- column-wise part:
        -- propagate stage 1 and check when reaching last font column to
        -- increment counter
        -----------------------------------------------------------------------
        s2_Is_backg <= s1_Is_backg;
        s2_Is_font  <= s1_Is_font;
        s2_Is_SF    <= s1_Is_SF;
        s2_Font_row <= s1_Font_row;
        s2_Font_col <= s1_Font_col;
        s2_SF_row   <= s1_SF_row;
        s2_SF_col   <= s1_SF_col;
        if (s2_SF_col = 2) then
          if ((s2_Font_cnt + 1) = sB) then
            s2_Font_cnt <= 0;
          else
            s2_Font_cnt <= s2_Font_cnt + 1;
          end if;
        end if;
      else
        s2_Is_bar   <= '0';
        s2_Bar_idx  <= 0;
        s2_Is_backg <= '0';
        s2_Is_font  <= '0';
        s2_Is_SF    <= '0';
        s2_Font_row <= 0;
        s2_Font_col <= 0;
        s2_SF_row   <= 0;
        s2_SF_col   <= 0;
        s2_Font_cnt <= 0;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Color selection network:
  -- * 1) First check if forcing background
  -- * 2) Second check if it is a font, if so find the position in the array with
  --   the note names, then depending of the scale set the note name.
  --   Then depending on the scale type (sharp or flat) get the font element from the proper array
  --   and if the note name requires a sharp or a flat add it (notes requiring
  --   sharp or flat are CD, DE, FG, GA and AB) otherwise set the background color
  -- * 3) Third check if it is a bar, if so find the position in the palette
  --   array with note colors and set the note color
  -- * 4) Else default to background
  -----------------------------------------------------------------------------
  process (s2_Is_backg, s2_Is_font, s2_Is_SF, s2_Font_row, s2_Font_col, s2_Font_cnt, s2_SF_row, s2_SF_col, s2_Is_bar, s2_Bar_idx, ROOT_NOTE, PALETTE_POS, SCALE_TYPE) is
    variable vPalette_idx : integer;
    variable vFont_idx    : integer;
  begin  -- process
    -- 1) Forcing background
    if (s2_Is_backg = '1') then
      s23_R_i <= cBACKGROUND.R;
      s23_G_i <= cBACKGROUND.G;
      s23_B_i <= cBACKGROUND.B;
    -- 2) Managing fonts
    elsif (s2_Is_font = '1') then
      vFont_idx := to_integer(ROOT_NOTE) + PALETTE_POS(s2_Font_cnt);
      if (vFont_idx > 11) then
        vFont_idx := vFont_idx - 12;
      end if;
      if (s2_Is_SF = '0') then          -- font but not #/b
        if (SCALE_TYPE(0) = cIS_SHARP) then    -- scale is sharp
          s23_R_i <= (others => cFont6x7_array_sharp(vFont_idx)(s2_Font_row)(s2_Font_col));
          s23_G_i <= (others => cFont6x7_array_sharp(vFont_idx)(s2_Font_row)(s2_Font_col));
          s23_B_i <= (others => cFont6x7_array_sharp(vFont_idx)(s2_Font_row)(s2_Font_col));
        else                            -- scale is flat
          s23_R_i <= (others => cFont6x7_array_flat(vFont_idx)(s2_Font_row)(s2_Font_col));
          s23_G_i <= (others => cFont6x7_array_flat(vFont_idx)(s2_Font_row)(s2_Font_col));
          s23_B_i <= (others => cFont6x7_array_flat(vFont_idx)(s2_Font_row)(s2_Font_col));
        end if;
      else                              -- font is #/b
        if ((vFont_idx = cCD_NOTE) or (vFont_idx = cDE_NOTE) or (vFont_idx = cFG_NOTE) or (vFont_idx = cGA_NOTE) or (vFont_idx = cAB_NOTE)) then
          if (SCALE_TYPE(0) = cIS_SHARP) then  -- scale is sharp
            s23_R_i <= (others => cFONT_SHARP(s2_SF_row)(s2_SF_col));
            s23_G_i <= (others => cFONT_SHARP(s2_SF_row)(s2_SF_col));
            s23_B_i <= (others => cFONT_SHARP(s2_SF_row)(s2_SF_col));
          else                          -- scale is flat
            s23_R_i <= (others => cFONT_FLAT(s2_SF_row)(s2_SF_col));
            s23_G_i <= (others => cFONT_FLAT(s2_SF_row)(s2_SF_col));
            s23_B_i <= (others => cFONT_FLAT(s2_SF_row)(s2_SF_col));
          end if;
        else  -- note has neither # nor b -> so it is background
          s23_R_i <= cBACKGROUND.R;
          s23_G_i <= cBACKGROUND.G;
          s23_B_i <= cBACKGROUND.B;
        end if;
      end if;
    elsif (s2_Is_bar = '1') then
      vPalette_idx := to_integer(ROOT_NOTE) + PALETTE_POS(s2_Bar_idx);
      if (vPalette_idx > 11) then
        vPalette_idx := vPalette_idx - 12;
      end if;
      s23_R_i <= cPALETTE(vPalette_idx).R;
      s23_G_i <= cPALETTE(vPalette_idx).G;
      s23_B_i <= cPALETTE(vPalette_idx).B;
    -- 4) Default to background
    else
      s23_R_i <= cBACKGROUND.R;
      s23_G_i <= cBACKGROUND.G;
      s23_B_i <= cBACKGROUND.B;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Pipelin stage 3 (s3)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s3_de <= '0';
      s3_R_reg <= (others => '0');
      s3_G_reg <= (others => '0');
      s3_B_reg <= (others => '0');
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s3_de <= s2_de;
      if (s2_de = '1') then
        s3_R_reg <= s23_R_i;
        s3_G_reg <= s23_G_i;
        s3_B_reg <= s23_B_i;
      else
        s3_R_reg <= (others => '0');
        s3_G_reg <= (others => '0');
        s3_B_reg <= (others => '0');
      end if;
    end if;
  end process;

  DE_OUT <= s3_de;
  R_OUT <= s3_R_reg;
  G_OUT <= s3_G_reg;
  B_OUT <= s3_B_reg;

end architecture;
