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
-- Title      : PoliMorph
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : polimorph.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-27
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of a continuous touch
-- based synthesizer with sound morphing
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;
use work.notes_pkg.all;

entity polimorph is
  port (
    KEY                : in    std_logic_vector(3 downto 0);
    CLOCK_50           : in    std_logic;
    SW                 : in    std_logic_vector(9 downto 0);
    LEDR               : out   std_logic_vector(9 downto 0);
    HEX0               : out   std_logic_vector(0 to 6);
    HEX1               : out   std_logic_vector(0 to 6);
    HEX2               : out   std_logic_vector(0 to 6);
    HEX3               : out   std_logic_vector(0 to 6);
    HEX4               : out   std_logic_vector(0 to 6);
    HEX5               : out   std_logic_vector(0 to 6);
    MTL2_R             : out   unsigned(7 downto 0);
    MTL2_G             : out   unsigned(7 downto 0);
    MTL2_B             : out   unsigned(7 downto 0);
    MTL2_DCLK          : out   std_logic;
    MTL2_HSD           : out   std_logic;
    MTL2_VSD           : out   std_logic;
    MTL2_TOUCH_I2C_SCL : inout std_logic;
    MTL2_TOUCH_I2C_SDA : inout std_logic;
    MTL2_TOUCH_INT_n   : in    std_logic;
    FPGA_I2C_SCLK      : out   std_logic;
    FPGA_I2C_SDAT      : inout std_logic;
    AUD_XCK            : out   std_logic;
    AUD_DACLRCK        : in    std_logic;
    AUD_ADCLRCK        : in    std_logic;
    AUD_BCLK           : in    std_logic;
    AUD_ADCDAT         : in    std_logic;
    AUD_DACDAT         : out   std_logic
    );
end polimorph;

architecture beh of polimorph is

  constant tco : time := 2 ns;
  constant tpd : time := 2 ns;

  constant cN_NOTES : integer := 12;

  -----------------------------------------------------------------------------
  -- Local design constants
  -----------------------------------------------------------------------------

  constant cH_RED : integer := cH_THR2 + cW/2;
  constant cV_RED : integer := cV_THR2 + cH/2;

  component pll33 is
    port (
      refclk   : in  std_logic := '0';
      rst      : in  std_logic := '0';
      outclk_0 : out std_logic;
      locked   : out std_logic);
  end component pll33;

  component control_decoder is
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
  end component control_decoder;

  component note_indicator is
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
      HPOS         : in  unsigned(cW_MTL2_NBIT-1 downto 0);
      VPOS         : in  unsigned(cH_MTL2_NBIT-1 downto 0);
      DE_IN        : in  std_logic;
      R_OUT        : out unsigned(7 downto 0);
      G_OUT        : out unsigned(7 downto 0);
      B_OUT        : out unsigned(7 downto 0);
      DE_OUT       : out std_logic);
  end component note_indicator;

  component dec7seg_hex is
    port (
      DIN  : in  std_logic_vector(3 downto 0);
      DOUT : out std_logic_vector(0 to 6));
  end component dec7seg_hex;

  component dec7seg_lock is
    port (
      PITCH_LOCKED : in  std_logic;
      HEX          : out std_logic_vector(0 to 6));
  end component dec7seg_lock;

  component dec7seg_scale is
    port (
      SW_SCALE : in  std_logic_vector(3 downto 0);
      DOUT0    : out std_logic_vector(0 to 6);
      DOUT1    : out std_logic_vector(0 to 6);
      DOUT2    : out std_logic_vector(0 to 6));
  end component dec7seg_scale;

  component i2c_touch_config is
    port (
      iCLK : in std_logic;
      iRSTN : in std_logic;
      oREADY : out std_logic;
      INT_n : in std_logic;
      oREG_X1 : out unsigned(9 downto 0);
      oREG_Y1 : out unsigned(8 downto 0);
      oREG_X2 : out unsigned(9 downto 0);
      oREG_Y2 : out unsigned(8 downto 0);
      oREG_X3 : out unsigned(9 downto 0);
      oREG_Y3 : out unsigned(8 downto 0);
      oREG_X4 : out unsigned(9 downto 0);
      oREG_Y4 : out unsigned(8 downto 0);
      oREG_X5 : out unsigned(9 downto 0);
      oREG_Y5 : out unsigned(8 downto 0);
      oREG_GESTURE : out unsigned(7 downto 0);
      oREG_TOUCH_COUNT : out unsigned(3 downto 0);
      I2C_SDAT : inout std_logic;
      I2C_SCLK : inout std_logic);
  end component i2c_touch_config;

  component touch_interface is
    port (
      CLK50           : in  std_logic;
      RST_n           : in  std_logic;
      TOUCH_ARRAY_IN  : in  tTouchPosition;
      TOUCH_READY_IN  : in  std_logic;
      TOUCH_COUNT_IN  : in  unsigned(3 downto 0);
      CLK33           : in  std_logic;
      TOUCH_ARRAY_OUT : out tTouchPosition;
      TOUCH_READY_OUT : out std_logic;
      TOUCH_COUNT_OUT : out unsigned(3 downto 0);
      TOUCH_ACK_IN    : in  std_logic
      );
  end component touch_interface;

  component touch_manager is
    port (
      CLK                : in  std_logic;
      RST_n              : in  std_logic;
      TOUCH_CNT_IN       : in  unsigned(3 downto 0);
      TOUCH_POSITION_IN  : in  tTouchPosition;
      TOUCH_READY_IN     : in  std_logic;
      TOUCH_ACK_OUT      : out std_logic;
      TOUCH_CNT_OUT      : out unsigned(3 downto 0);
      TOUCH_POSITION_OUT : out tTouchPosition;
      TOUCH_VALID_OUT    : out std_logic_vector(cN_MTL2_TOUCH-1 downto 0));
  end component touch_manager;

  component touch_renderer is
    generic (
      IDX : integer);
    port (
      CLK         : in  std_logic;
      RST_n       : in  std_logic;
      TOUCH_POS   : in  rTouchPosition;
      TOUCH_VALID : in  std_logic;
      HPOS        : in  unsigned(cW_MTL2_NBIT-1 downto 0);
      VPOS        : in  unsigned(cH_MTL2_NBIT-1 downto 0);
      DE_IN       : in  std_logic;
      R_OUT       : out unsigned(7 downto 0);
      G_OUT       : out unsigned(7 downto 0);
      B_OUT       : out unsigned(7 downto 0);
      DE_OUT      : out std_logic);
  end component touch_renderer;

  component dds_mapper is
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
      DDS_VALID_OUT  : out std_logic);
  end component dds_mapper;

  component dds_synch is
    port (
      CLK33          : in  std_logic;
      RST_n          : in  std_logic;
      MORPH_FACT_IN  : in  unsigned(cH_MTL2_NBIT-1 downto 0);
      DDS_PHASE_IN   : in  unsigned(cNBIT_DDS_Phase-1 downto 0);
      DDS_VALID_IN   : in  std_logic;
      CLK50          : in  std_logic;
      MORPH_FACT_OUT : out unsigned(cH_MTL2_NBIT-1 downto 0);
      DDS_PHASE_OUT  : out unsigned(cNBIT_DDS_Phase-1 downto 0);
      DDS_VALID_OUT  : out std_logic);
  end component dds_synch;

  component dds_osc is
    port (
      CLK          : in  std_logic;
      RST_n        : in  std_logic;
      ADVANCE      : in  std_logic;
      DDS_VALID_IN : in  std_logic;
      PHASE_INC    : in  unsigned(23 downto 0);
      MORPH_Y      : in  unsigned(8 downto 0);
      AUDIO_OUT    : out signed(20 downto 0);
      AUDIO_VALID  : out std_logic);
  end component dds_osc;

  component wm8731_driver is
    port (
      CLOCK_50      : in    std_logic;
      RESET_n       : in    std_logic;
      FPGA_I2C_SCLK : out   std_logic;
      FPGA_I2C_SDAT : inout std_logic;
      AUD_XCK       : out   std_logic;
      AUD_BCLK      : in    std_logic;
      AUD_DACLRCK   : in    std_logic;
      AUD_ADCLRCK   : in    std_logic;
      AUD_ADCDAT    : in    std_logic;
      AUD_DACDAT    : out   std_logic;
      DAC_LEFT      : in    std_logic_vector(23 downto 0);
      DAC_RIGHT     : in    std_logic_vector(23 downto 0);
      ADC_LEFT      : out   std_logic_vector(23 downto 0);
      ADC_RIGHT     : out   std_logic_vector(23 downto 0);
      ADVANCE       : out   std_logic);
  end component wm8731_driver;

  signal button_rst_n : std_logic;
  signal pll_rst : std_logic;
  signal clk33 : std_logic;
  signal locked : std_logic;
  signal rst_n : std_logic;

  signal sRoot_Note    : unsigned(3 downto 0);
  signal sN_Octaves    : unsigned(2 downto 0);
  signal sOctave_Start : unsigned(2 downto 0);
  signal sScale_Mask   : std_logic_vector(11 downto 0);
  signal sScale_Len    : unsigned(3 downto 0);
  signal sScale_Type   : std_logic_vector(1 downto 0);
  signal sN_Semitones  : unsigned(5 downto 0);
  signal sPalette_Pos  : tPalette_Pos_Array;
  signal sPitch_Locked : std_logic;

  signal sHcnt : unsigned(cH_NBIT-1 downto 0);
  signal sHcnt_tc : std_logic;
  signal sVcnt : unsigned(cV_NBIT-1 downto 0);
  signal sVcnt_tc : std_logic;

  signal sH_is_pulse : std_logic;
  signal sH_is_bp : std_logic;
  signal sH_is_w : std_logic;
  signal sH_is_fp : std_logic;

  signal sH_x_pos : unsigned(cW_MTL2_NBIT-1 downto 0);

  signal sVGA_HS : std_logic;
  signal sVGA_HS_reg1 : std_logic;
  signal sVGA_HS_reg2 : std_logic;
  signal sVGA_HS_reg3 : std_logic;

  signal sV_is_pulse : std_logic;
  signal sV_is_bp : std_logic;
  signal sV_is_h : std_logic;
  signal sV_is_fp : std_logic;

  signal sV_y_pos : unsigned(cH_MTL2_NBIT-1 downto 0);

  signal sVideo_on : std_logic;

  signal sNote_Ind_R : unsigned(7 downto 0);
  signal sNote_Ind_G : unsigned(7 downto 0);
  signal sNote_Ind_B : unsigned(7 downto 0);

  signal sVGA_VS : std_logic;
  signal sVGA_VS_reg1 : std_logic;
  signal sVGA_VS_reg2 : std_logic;
  signal sVGA_VS_reg3 : std_logic;

  signal sTouchReady_50MHz : std_logic;
  signal sTouchPosition_50MHz : tTouchPosition;
  signal sTouchCount_50MHz : unsigned(3 downto 0);

  signal sTouchReady_33MHz : std_logic;
  signal sTouchPosition_33MHz : tTouchPosition;
  signal sTouchCount_33MHz: unsigned(3 downto 0);
  signal sTouchAck_33MHz : std_logic;

  signal sTouchCount_track : unsigned(3 downto 0);
  signal sTouchPosition_track : tTouchPosition;
  signal sTouchValid_track : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);

  type tTouchComponent is array (0 to cN_MTL2_TOUCH-1) of unsigned(7 downto 0);
  signal sTouch_rend_R : tTouchComponent;
  signal sTouch_rend_G : tTouchComponent;
  signal sTouch_rend_B : tTouchComponent;

  type tDDS_Phase_array is array (0 to cN_MTL2_TOUCH-1) of unsigned(cNBIT_DDS_Phase-1 downto 0);
  signal sDDS_Phase_Value_33MHz : tDDS_Phase_array;
  signal sDDS_Phase_Value_50MHz : tDDS_Phase_array;
  signal sDDS_Phase_Valid_33MHz : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);
  signal sDDS_Phase_Valid_50MHz : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);

  type tMorph_Fact_array is array (0 to cN_MTL2_TOUCH-1) of unsigned(cH_MTL2_NBIT-1 downto 0);
  signal sMorph_Fact_33MHz : tMorph_Fact_array;
  signal sMorph_Fact_50MHz : tMorph_Fact_array;

  signal sAdvance : std_logic;
  type tAudio_array is array (0 to cN_MTL2_TOUCH-1) of signed(20 downto 0);
  signal sAudio_val : tAudio_array;
  signal sDAC_left : signed(23 downto 0);
  signal sDAC_right : signed(23 downto 0);

  signal sSW_Scale_reg : std_logic_vector(3 downto 0);

begin  -- beh

  -----------------------------------------------------------------------------
  -- Clock and reset management with PLL
  -----------------------------------------------------------------------------

  -- reset pressing KEY(3) and KEY(0) concurrently
  button_rst_n <= KEY(3) or KEY(0);

  -- PLL reset is the button (pll reset is active high)
  pll_rst <= not(button_rst_n);

  pll33_i: pll33
    port map (
      refclk   => CLOCK_50,
      rst      => pll_rst,
      outclk_0 => clk33,
      locked   => locked);
  MTL2_DCLK <= clk33;

  -- circuit reset is released when both button is released and PLL is locked
  rst_n <= button_rst_n and locked;

  -----------------------------------------------------------------------------
  -- SW and key paramters
  -----------------------------------------------------------------------------
  cd : control_decoder
    port map (
      CLK          => clk33,
      RST_n        => rst_n,
      SW           => SW,
      KEY          => KEY,
      ROOT_NOTE    => sRoot_Note,
      N_OCTAVES    => sN_Octaves,
      OCTAVE_START => sOctave_Start,
      SCALE_MASK   => sScale_Mask,
      SCALE_LEN    => sScale_Len,
      SCALE_TYPE   => sScale_Type,
      N_SEMITONES  => sN_Semitones,
      PALETTE_POS  => sPalette_Pos,
      PITCH_LOCKED => sPitch_Locked
      );

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- LCD MANAGEMENT PART
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------

  -----------------------------------------------------------------------------
  -- Horizontal and Vertical Sync
  -----------------------------------------------------------------------------

  -- horizontal counter
  process (clk33, rst_n)
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      sHcnt <= (others => '0') after tco;
    elsif clk33'event and clk33 = '1' then  -- rising clock edge
      if sHcnt_tc = '1' then
        sHcnt <= (others => '0') after tco;
      else
        sHcnt <= sHcnt + 1 after tco;
      end if;
    end if;
  end process;

  -- horizontal counter comparators
  process (sHcnt)
  begin  -- process
    sH_is_pulse <= '0' after tpd;
    sH_is_bp <= '0' after tpd;
    sH_is_w <= '0' after tpd;
    sH_is_fp <= '0' after tpd;
    sHcnt_tc <= '0' after tpd;
    sH_x_pos <= (others => '0') after tpd;
    if (to_integer(sHcnt) < cH_THR1) then
      sH_is_pulse <= '1' after tpd;
      sH_is_bp <= '1' after tpd;
    else
      if (to_integer(sHcnt) < cH_THR2) then
        sH_is_bp <= '1' after tpd;
      else
        if (to_integer(sHcnt) < cH_THR3) then
          sH_is_w <= '1' after tpd;
          sH_x_pos <= to_unsigned(to_integer(sHcnt) - cH_THR2, cW_MTL2_NBIT) after tpd;
        else
          sH_is_fp <= '1' after tpd;
          if (to_integer(sHcnt) = cH_TC) then
            sHcnt_tc <= '1' after tpd;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- horizontal sync
  sVGA_HS <= '0' after tpd when sH_is_pulse = '1' else '1' after tpd;

  -- vertical counter
  process (clk33, rst_n)
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      sVcnt <= (others => '0') after tco;
    elsif clk33'event and clk33 = '1' then  -- rising clock edge
      if (sVcnt_tc = '1' and sHcnt_tc = '1') then
        sVcnt <= (others => '0') after tco;
      else
        if (sHcnt_tc = '1') then
          sVcnt <= sVcnt + 1 after tco;
        end if;
      end if;
    end if;
  end process;

  -- vertical counter comparators
  process (sVcnt)
  begin  -- process
    sV_is_pulse <= '0' after tpd;
    sV_is_bp <= '0' after tpd;
    sV_is_h <= '0' after tpd;
    sV_is_fp <= '0' after tpd;
    sVcnt_tc <= '0' after tpd;
    sV_y_pos <= (others => '0') after tpd;
    if (to_integer(sVcnt) < cV_THR1) then
      sV_is_pulse <= '1' after tpd;
      sV_is_bp <= '1' after tpd;
    else
      if (to_integer(sVcnt) < cV_THR2) then
        sV_is_bp <= '1' after tpd;
      else
        if (to_integer(sVcnt) < cV_THR3) then
          sV_is_h <= '1' after tpd;
          sV_y_pos <= to_unsigned(to_integer(sVcnt) - cV_THR2, cH_MTL2_NBIT) after tpd;
        else
          sV_is_fp <= '1' after tpd;
          if (to_integer(sVcnt) = cV_TC) then
            sVcnt_tc <= '1' after tpd;
          end if;
        end if;
      end if;
    end if;
  end process;

  -- Vertical sync
  sVGA_VS <= '0' after tpd when sV_is_pulse = '1' else '1' after tpd;

  -- video on signal
  sVideo_on <= sH_is_w and sV_is_h after tpd;

  ni : note_indicator
    port map (
      CLK          => clk33,
      RST_n        => rst_n,
      ROOT_NOTE    => sRoot_Note,
      N_OCTAVES    => sN_Octaves,
      OCTAVE_START => sOctave_Start,
      SCALE_MASK   => sScale_Mask,
      SCALE_LEN    => sScale_Len,
      SCALE_TYPE   => sScale_Type,
      N_SEMITONES  => sN_Semitones,
      PALETTE_POS  => sPalette_Pos,
      HPOS         => sH_x_pos,
      VPOS         => sV_y_pos,
      DE_IN        => sVideo_on,
      R_OUT        => sNote_Ind_R,
      G_OUT        => sNote_Ind_G,
      B_OUT        => sNote_Ind_B,
      DE_OUT       => open);

  -- delay H and V sync signals by three clock cycles to align with data
  process (clk33, rst_n)
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      sVGA_HS_reg1 <= '1' after tco;
      sVGA_VS_reg1 <= '1' after tco;
      sVGA_HS_reg2 <= '1' after tco;
      sVGA_VS_reg2 <= '1' after tco;
      sVGA_HS_reg3 <= '1' after tco;
      sVGA_VS_reg3 <= '1' after tco;
    elsif clk33'event and clk33 = '1' then  -- rising clock edge
      sVGA_HS_reg1 <= sVGA_HS after tco;
      sVGA_VS_reg1 <= sVGA_VS after tco;
      sVGA_HS_reg2 <= sVGA_HS_reg1;
      sVGA_VS_reg2 <= sVGA_VS_reg1;
      sVGA_HS_reg3 <= sVGA_HS_reg2;
      sVGA_VS_reg3 <= sVGA_VS_reg2;
    end if;
  end process;

  MTL2_HSD <= sVGA_HS_reg3;
  MTL2_VSD <= sVGA_VS_reg3;

  -----------------------------------------------------------------------------
  -- RED mix
  -----------------------------------------------------------------------------
  process (sNote_Ind_R, sTouch_rend_R) is
    variable tmp : unsigned(10 downto 0);
  begin  -- process
    tmp := resize(sNote_Ind_R, 11);
    for idx in 0 to cN_MTL2_TOUCH-1 loop
      tmp := tmp + resize(sTouch_rend_R(idx), 11);
    end loop;  -- idx
    if (to_integer(tmp) > 255) then
      MTL2_R <= to_unsigned(255, 8);
    else
      MTL2_R <= tmp(7 downto 0);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- GREEN mix
  -----------------------------------------------------------------------------
  process (sNote_Ind_G, sTouch_rend_G) is
    variable tmp : unsigned(10 downto 0);
  begin  -- process
    tmp := resize(sNote_Ind_G, 11);
    for idx in 0 to cN_MTL2_TOUCH-1 loop
      tmp := tmp + resize(sTouch_rend_G(idx), 11);
    end loop;  -- idx
    if (to_integer(tmp) > 255) then
      MTL2_G <= to_unsigned(255, 8);
    else
      MTL2_G <= tmp(7 downto 0);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- BLUE mix
  -----------------------------------------------------------------------------
  process (sNote_Ind_B, sTouch_rend_B) is
    variable tmp : unsigned(10 downto 0);
  begin  -- process
    tmp := resize(sNote_Ind_B, 11);
    for idx in 0 to cN_MTL2_TOUCH-1 loop
      tmp := tmp + resize(sTouch_rend_B(idx), 11);
    end loop;  -- idx
    if (to_integer(tmp) > 255) then
      MTL2_B <= to_unsigned(255, 8);
    else
      MTL2_B <= tmp(7 downto 0);
    end if;
  end process;

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- TOUCH MANAGEMENT PART
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------

  i2c_touch_config_i : i2c_touch_config
    port map (
      iCLK             => CLOCK_50,
      iRSTN            => rst_n,
      oREADY           => sTouchReady_50MHz,
      INT_n            => MTL2_TOUCH_INT_n,
      oREG_X1          => sTouchPosition_50MHz(0).x,
      oREG_Y1          => sTouchPosition_50MHz(0).y,
      oREG_X2          => sTouchPosition_50MHz(1).x,
      oREG_Y2          => sTouchPosition_50MHz(1).y,
      oREG_X3          => sTouchPosition_50MHz(2).x,
      oREG_Y3          => sTouchPosition_50MHz(2).y,
      oREG_X4          => sTouchPosition_50MHz(3).x,
      oREG_Y4          => sTouchPosition_50MHz(3).y,
      oREG_X5          => sTouchPosition_50MHz(4).x,
      oREG_Y5          => sTouchPosition_50MHz(4).y,
      oREG_GESTURE     => open,
      oREG_TOUCH_COUNT => sTouchCount_50MHz,
      I2C_SDAT         => MTL2_TOUCH_I2C_SDA,
      I2C_SCLK         => MTL2_TOUCH_I2C_SCL);

  ti : touch_interface
    port map (
      CLK50           => CLOCK_50,
      RST_n           => rst_n,
      TOUCH_ARRAY_IN  => sTouchPosition_50MHz,
      TOUCH_READY_IN  => sTouchReady_50MHz,
      TOUCH_COUNT_IN  => sTouchCount_50MHz,
      CLK33           => clk33,
      TOUCH_ARRAY_OUT => sTouchPosition_33MHz,
      TOUCH_READY_OUT => sTouchReady_33MHz,
      TOUCH_COUNT_OUT => sTouchCount_33MHz,
      TOUCH_ACK_IN    => sTouchAck_33MHz);

  tm : touch_manager
    port map (
      CLK                => clk33,
      RST_n              => rst_n,
      TOUCH_CNT_IN       => sTouchCount_33MHz,
      TOUCH_POSITION_IN  => sTouchPosition_33MHz,
      TOUCH_READY_IN     => sTouchReady_33MHz,
      TOUCH_ACK_OUT      => sTouchAck_33MHz,
      TOUCH_CNT_OUT      => sTouchCount_track,
      TOUCH_POSITION_OUT => sTouchPosition_track,
      TOUCH_VALID_OUT    => sTouchValid_track);

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- TOUCH RENDERING AND SOUND GENERATION PART
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------

  tr_loop : for idx in 0 to cN_MTL2_TOUCH-1 generate

    tr_i : touch_renderer
      generic map (
        IDX => idx)
      port map (
        CLK         => clk33,
        RST_n       => rst_n,
        TOUCH_POS   => sTouchPosition_track(idx),
        TOUCH_VALID => sTouchValid_track(idx),
        HPOS        => sH_x_pos,
        VPOS        => sV_y_pos,
        DE_IN       => sVideo_on,
        R_OUT       => sTouch_rend_R(idx),
        G_OUT       => sTouch_rend_G(idx),
        B_OUT       => sTouch_rend_B(idx),
        DE_OUT      => open);

    dds_m_i : dds_mapper
      port map (
        CLK            => clk33,
        RST_n          => rst_n,
        ROOT_NOTE      => sRoot_Note,
        N_OCTAVES      => sN_Octaves,
        OCTAVE_START   => sOctave_Start,
        SCALE_LEN      => sScale_Len,
        N_SEMITONES    => sN_Semitones,
        PALETTE_POS    => sPalette_Pos,
        PITCH_LOCKED   => sPitch_Locked,
        TOUCH_POS_IN   => sTouchPosition_track(idx),
        TOUCH_VALID_IN => sTouchValid_track(idx),
        MORPH_FACT_OUT => sMorph_Fact_33MHz(idx),
        DDS_PHASE_OUT  => sDDS_Phase_Value_33MHz(idx),
        DDS_VALID_OUT  => sDDS_Phase_Valid_33MHz(idx));

    dds_s_i : dds_synch
      port map (
        CLK33          => clk33,
        RST_n          => rst_n,
        MORPH_FACT_IN  => sMorph_Fact_33MHz(idx),
        DDS_PHASE_IN   => sDDS_Phase_Value_33MHz(idx),
        DDS_VALID_IN   => sDDS_Phase_Valid_33MHz(idx),
        CLK50          => CLOCK_50,
        MORPH_FACT_OUT => sMorph_Fact_50MHz(idx),
        DDS_PHASE_OUT  => sDDS_Phase_Value_50MHz(idx),
        DDS_VALID_OUT  => sDDS_Phase_Valid_50MHz(idx));

    dds_o_i : dds_osc
      port map (
        CLK          => CLOCK_50,
        RST_n        => rst_n,
        ADVANCE      => sAdvance,
        DDS_VALID_IN => sDDS_Phase_Valid_50MHz(idx),
        PHASE_INC    => sDDS_Phase_Value_50MHz(idx),
        MORPH_Y      => sMorph_Fact_50MHz(idx),
        AUDIO_OUT    => sAudio_val(idx),
        AUDIO_VALID  => open);

  end generate tr_loop;

  process (sAudio_val) is
    variable tmp : signed(23 downto 0);
  begin  -- process
    tmp := (others => '0');
    for idx in 0 to cN_MTL2_TOUCH-1 loop
      tmp := tmp + sAudio_val(idx);
    end loop;  -- idx
    sDAC_left <= tmp;
    sDAC_right <= tmp;
  end process;

  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------
  -- AUDIO DRIVER
  -----------------------------------------------------------------------------
  -----------------------------------------------------------------------------

    wm8731_audio_driver : wm8731_driver
      port map (
        CLOCK_50      => CLOCK_50,
        RESET_n       => rst_n,
        FPGA_I2C_SCLK => FPGA_I2C_SCLK,
        FPGA_I2C_SDAT => FPGA_I2C_SDAT,
        AUD_XCK       => AUD_XCK,
        AUD_BCLK      => AUD_BCLK,
        AUD_DACLRCK   => AUD_DACLRCK,
        AUD_ADCLRCK   => AUD_ADCLRCK,
        AUD_ADCDAT    => AUD_ADCDAT,
        AUD_DACDAT    => AUD_DACDAT,
        DAC_LEFT      => std_logic_vector(sDAC_left),
        DAC_RIGHT     => std_logic_vector(sDAC_right),
        ADC_LEFT      => open,
        ADC_RIGHT     => open,
        ADVANCE       => sAdvance);

  -----------------------------------------------------------------------------
  -- Output on LEDs and HEXs
  -----------------------------------------------------------------------------

  LEDR(9 downto 5) <= (others => '0');
  LEDR(4 downto 0) <= sDDS_Phase_Valid_50MHz;

  dec7seg_hex_0 : dec7seg_hex
    port map (
      DIN  => std_logic_vector(resize(sOctave_Start, 4)),
      DOUT => HEX0);

  dec7seg_hex_1 : dec7seg_hex
    port map (
      DIN  => std_logic_vector(sTouchCount_track),
      DOUT => HEX1);

  dec7seg_lock2 : dec7seg_lock
    port map (
      PITCH_LOCKED => sPitch_Locked,
      HEX          => HEX2);

  process (CLOCK_50, rst_n) is
  begin  -- process
    if rst_n = '0' then                 -- asynchronous reset (active low)
      sSW_Scale_reg <= (others => '0');
    elsif CLOCK_50'event and CLOCK_50 = '1' then  -- rising clock edge
      sSW_Scale_reg <= SW(9 downto 6);
    end if;
  end process;

  dec7seg_scale345: dec7seg_scale
    port map (
      SW_SCALE => sSW_Scale_reg,
      DOUT0    => HEX3,
      DOUT1    => HEX4,
      DOUT2    => HEX5);

end beh;
