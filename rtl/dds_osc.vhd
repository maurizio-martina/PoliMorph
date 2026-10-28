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
-- Title      : DDS oscillator
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dds_osc.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-23
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of the DDS. It contains
-- two ROMs 1) a sine; 2) a harmonic rich wave which are morphed together as
-- function of Y touch coordinate. The DDS receives a 48 kHz advance signal
-- from the DAC interface and produces a new sample. The DDS implements also an
-- interpolator: each ROM outputs two consecutive values using the most significant part of
-- the phase accumulator as the ROM address and the least significant part of
-- the phase accumulator as the weight for combining the two consecutive samples.
-- Pipeline 5 stages
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use ieee.math_real.all;

library work;
use work.wavetable_pkg.all;

entity dds_osc is
  port (
    CLK         : in  std_logic;
    RST_n       : in  std_logic;
    ADVANCE     : in  std_logic;           -- 48 kHz (from wm8731_driver)
    DDS_VALID_IN : in std_logic;
    PHASE_INC   : in  unsigned(23 downto 0);
    MORPH_Y     : in  unsigned(8 downto 0);
    AUDIO_OUT   : out signed(20 downto 0);
    AUDIO_VALID : out std_logic
  );
end entity dds_osc;

architecture rtl of dds_osc is

  -- ----------------------------------------------------------
  -- Morphing constants
  -- ----------------------------------------------------------
  constant cMORPH_LO  : integer               := 66;   -- lower Y bound
  constant cMORPH_HI  : integer               := 450;  -- upper Y bound
  constant cMORPH_RNG : integer               := cMORPH_HI - cMORPH_LO;
  constant cMORPH_K   : unsigned(15 downto 0) := to_unsigned(43520, 16);

  -- ----------------------------------------------------------
  -- Initialize sine ROM
  -- ----------------------------------------------------------
  function fInit_Sine_ROM return wavetable_t is
    -- reduced peak to account for lower RMS value of the wavetable to avoid
    -- abrubt volume change during morphing
    constant cSIN_PEAK : integer := 23790;
    variable rom : wavetable_t;
    variable v   : integer;
  begin
    for i in 0 to WAVE_SIZE - 1 loop
      v := integer(round(
             sin(real(i) * MATH_2_PI / real(WAVE_SIZE)) * real(cSIN_PEAK)));
      if v > cSIN_PEAK then v := cSIN_PEAK; end if;
      if v < -cSIN_PEAK then v := -cSIN_PEAK; end if;
      rom(i) := to_signed(v, 16);
    end loop;
    return rom;
  end function fInit_Sine_ROM;

  -- ----------------------------------------------------------
  -- Wave ROMs
  -- ----------------------------------------------------------
  signal ROM_SINE : wavetable_t := fInit_Sine_ROM;
  signal ROM_WAVE : wavetable_t := WAVETABLE_B;

  attribute ramstyle : string;
  attribute ramstyle of ROM_SINE : signal is "M10K, no_rw_check";
  attribute ramstyle of ROM_WAVE : signal is "M10K, no_rw_check";

  -- ----------------------------------------------------------
  -- Phase accumulator
  -- ----------------------------------------------------------
  signal phase_acc : unsigned(23 downto 0) := (others => '0');

  -- ----------------------------------------------------------
  -- Stage 0
  -- ----------------------------------------------------------
  signal s0_valid   : std_logic;
  signal s0_addr_n  : unsigned(10 downto 0);  -- address sample N in ROM
  signal s0_addr_n1 : unsigned(10 downto 0);  -- address sample N+1 in ROM
  signal s0_sub_ph  : unsigned(5 downto 0);   -- sub-phase 0..63

  -- DSP morph-norm
  signal y_clamped  : unsigned(8 downto 0);
  signal morph_prod : unsigned(24 downto 0);

  -- ----------------------------------------------------------
  -- Stage 1
  -- ----------------------------------------------------------
  signal s1_valid   : std_logic;
  signal s1_sub_ph  : unsigned(5 downto 0);
  signal s1_morph_8 : unsigned(7 downto 0);
  signal s1_sine_N  : signed(15 downto 0);
  signal s1_sine_N1 : signed(15 downto 0);
  signal s1_wave_N  : signed(15 downto 0);
  signal s1_wave_N1 : signed(15 downto 0);

  -- ----------------------------------------------------------
  -- Stage 2
  -- delta = N1-N (17 bit signed) x sub_ph (7 bit signed) = 24 bit
  -- Cyclone V: preadder in DSP can host the subtraction
  -- ----------------------------------------------------------
  signal s2_valid    : std_logic;
  signal s2_morph    : unsigned(7 downto 0);
  signal s2_sine_N   : signed(16 downto 0);
  signal s2_wave_N   : signed(16 downto 0);
  signal s2_sine_dxk : signed(23 downto 0);
  signal s2_wave_dxk : signed(23 downto 0);

  -- ----------------------------------------------------------
  -- Stage 3
  -- (256-alpha) x sine_interp, alpha x wave_interp
  -- 10 bit x 17 bit = 27 bit signed
  -- ----------------------------------------------------------
  signal s3_valid   : std_logic;
  signal s3_morph_s : signed(26 downto 0);    -- (256-alpha) x sine_interp
  signal s3_morph_w : signed(26 downto 0);    -- alpha x wave_interp

begin

  -- ----------------------------------------------------------
  -- Clamp MORPH_Y to avoid display monitor (small Y) and note names (large Y)
  -- ----------------------------------------------------------
  y_clamped <=
    to_unsigned(cMORPH_RNG, 9) when to_integer(MORPH_Y) <= cMORPH_LO else
    to_unsigned(0,          9) when to_integer(MORPH_Y) >= cMORPH_HI else
    resize(to_unsigned(cMORPH_HI, 9) - MORPH_Y, 9);

  -- ----------------------------------------------------------
  -- Stage 0: phase accumulator + ROM addresses + weight for interpolation
  -- ----------------------------------------------------------
  p_stage0 : process (CLK, RST_n) begin
    if RST_n = '0' then
      phase_acc   <= (others => '0');
      s0_valid    <= '0';
      s0_addr_n   <= (others => '0');
      s0_addr_n1  <= (others => '0');
      s0_sub_ph   <= (others => '0');
      morph_prod  <= (others => '0');
    elsif rising_edge(CLK) then
      -- 9x16 bit multiplier -> DSP block
      morph_prod <= y_clamped * cMORPH_K;
      s0_valid <= DDS_VALID_IN;
      if ADVANCE = '1' then
        if (DDS_VALID_IN = '1') then
          -- First ROM address
          s0_addr_n  <= phase_acc(23 downto 13);
          -- Second ROM address (first+1) with wrap
          s0_addr_n1 <= phase_acc(23 downto 13) + 1;
          -- interpolation weight
          s0_sub_ph <= phase_acc(12 downto 7);
          -- phase accumulator
          phase_acc <= phase_acc + PHASE_INC;
        else
          phase_acc <= (others => '0');
        end if;
      end if;
    end if;
  end process p_stage0;

  -- ----------------------------------------------------------
  -- Stage 1: Dual-Port ROMs
  -- ----------------------------------------------------------
  -- 1) Sine
  p_rom_sine : process (CLK) begin
    if rising_edge(CLK) then
      s1_sine_N  <= ROM_SINE(to_integer(s0_addr_n));   -- port A
      s1_sine_N1 <= ROM_SINE(to_integer(s0_addr_n1));  -- port B
    end if;
  end process p_rom_sine;
  -- 2) Wavetable:
  p_rom_wave : process (CLK) begin
    if rising_edge(CLK) then
      s1_wave_N  <= ROM_WAVE(to_integer(s0_addr_n));
      s1_wave_N1 <= ROM_WAVE(to_integer(s0_addr_n1));
    end if;
  end process p_rom_wave;

  -- Delay signals to align with ROM timing
  p_stage1_ctrl : process (CLK, RST_n) begin
    if RST_n = '0' then
      s1_valid   <= '0';
      s1_sub_ph  <= (others => '0');
      s1_morph_8 <= (others => '0');
    elsif rising_edge(CLK) then
      s1_valid   <= s0_valid;
      s1_sub_ph  <= s0_sub_ph;
      -- Keep most significat part only as morphing factor
      s1_morph_8 <= morph_prod(23 downto 16);
    end if;
  end process p_stage1_ctrl;

  -- ----------------------------------------------------------
  -- Stage 2: interpolation delta
  -- ----------------------------------------------------------
  p_stage2 : process (CLK, RST_n) begin
    if RST_n = '0' then
      s2_valid    <= '0';
      s2_morph    <= (others => '0');
      s2_sine_N   <= (others => '0');
      s2_wave_N   <= (others => '0');
      s2_sine_dxk <= (others => '0');
      s2_wave_dxk <= (others => '0');
    elsif rising_edge(CLK) then
      s2_valid <= s1_valid;
      s2_morph <= s1_morph_8;
      s2_sine_N <= resize(s1_sine_N, 17);
      s2_wave_N <= resize(s1_wave_N, 17);
      -- delta x morph_factor
      -- Sine:
      s2_sine_dxk <=
        (resize(s1_sine_N1, 17) - resize(s1_sine_N, 17)) *
        signed('0' & s1_sub_ph);
      -- Wave:
      s2_wave_dxk <=
        (resize(s1_wave_N1, 17) - resize(s1_wave_N, 17)) *
        signed('0' & s1_sub_ph);
    end if;
  end process p_stage2;

  -- ----------------------------------------------------------
  -- Stage 3: interpolation and morphing
  -- ----------------------------------------------------------
  p_stage3 : process (CLK, RST_n) is
    variable sine_interp : signed(16 downto 0);
    variable wave_interp : signed(16 downto 0);
    variable alpha_s     : signed(9 downto 0);
    variable comp_s      : signed(9 downto 0);
  begin
    if RST_n = '0' then
      s3_valid   <= '0';
      s3_morph_s <= (others => '0');
      s3_morph_w <= (others => '0');
    elsif rising_edge(CLK) then
      s3_valid <= s2_valid;
      -- interpolated samples
      sine_interp := s2_sine_N +
                     resize(shift_right(s2_sine_dxk, 6), 17);
      wave_interp := s2_wave_N +
                     resize(shift_right(s2_wave_dxk, 6), 17);
      -- morph weights
      alpha_s := signed(resize(s2_morph, 10));
      comp_s  := to_signed(256, 10) - alpha_s;
      -- morphed elements
      s3_morph_s <= comp_s * sine_interp;
      s3_morph_w <= alpha_s * wave_interp;
    end if;
  end process p_stage3;

  -- ----------------------------------------------------------
  -- Stage 4: add morphed elements
  -- ----------------------------------------------------------
  p_stage4 : process (CLK, RST_n) is
    variable sum_v : signed(27 downto 0);
  begin
    if RST_n = '0' then
      AUDIO_OUT   <= (others => '0');
      AUDIO_VALID <= '0';
    elsif rising_edge(CLK) then
      AUDIO_VALID <= s3_valid;
      if (s3_valid = '1') then
        sum_v := resize(s3_morph_s, 28) + resize(s3_morph_w, 28);
      else
        sum_v := (others => '0');
      end if;
      AUDIO_OUT <= sum_v(23 downto 3);
    end if;
  end process p_stage4;

end architecture rtl;
