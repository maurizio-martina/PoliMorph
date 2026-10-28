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
-- Title      : Touch Renderer
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : touch_renderer.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the algorithm to render one touch position on
-- the LCD. Each touch has a different colour specified via the IDX generic
-- parameter. To visually show the sound morphing the touch is represented by a
-- different shape based on Y value.
-- It has 3 clock cycle latency
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;
use work.notes_pkg.all;

entity touch_renderer is
  generic (
    IDX : integer := 0
    );
  port (
    CLK : in std_logic;
    RST_n : in std_logic;
    TOUCH_POS : in rTouchPosition;
    TOUCH_VALID : in std_logic;
    HPOS  : in unsigned(cW_MTL2_NBIT-1 downto 0);
    VPOS  : in unsigned(cH_MTL2_NBIT-1 downto 0);
    DE_IN : in std_logic;
    R_OUT  : out unsigned(7 downto 0);
    G_OUT  : out unsigned(7 downto 0);
    B_OUT  : out unsigned(7 downto 0);
    DE_OUT : out std_logic
    );
end entity;

architecture rtl of touch_renderer is

  constant MORPH_NBIT : integer := 2;
  constant GLOW_RADIUS_NBIT : integer := 7;
  constant GLOW_RADIUS : integer := 2**GLOW_RADIUS_NBIT;
  constant GLOW_RADIUS_FACTOR : integer := 8-GLOW_RADIUS_NBIT;

  constant cY_CLIP_MIN : unsigned(cH_MTL2_NBIT-1 downto 0) := to_unsigned(20, cH_MTL2_NBIT);
  constant cY_CLIP_MAX : unsigned(cH_MTL2_NBIT-1 downto 0) := to_unsigned(400, cH_MTL2_NBIT);

  -- --------------------------------------------------------
  --  Stage 1: glow effects 1) touch distance; 2) y position
  -- --------------------------------------------------------
  signal s1_de : std_logic;
  signal s1_dist_fact : unsigned(7 downto 0);
  signal s1_morph_fact : unsigned(7 downto 0);
  signal s1_valid : std_logic;

  -- --------------------------------------------------------
  --  Stage 2: calculate the glow factor
  -- --------------------------------------------------------
  signal s2_de : std_logic;
  signal s2_glow_fact : unsigned(15 downto 0);
  signal s2_valid : std_logic;

  -- --------------------------------------------------------
  --  Stage 3: apply the glow factor
  -- --------------------------------------------------------
  signal s3_de : std_logic;
  signal s3_R_reg : unsigned(7 downto 0);
  signal s3_G_reg : unsigned(7 downto 0);
  signal s3_B_reg : unsigned(7 downto 0);
--  signal s3_valid : std_logic;

begin

  -----------------------------------------------------------------------------
  --  Stage 1 - horizontal and vertical distance from touch point to generate
  --  distance glow effect; vertical touch point generates position glow effect
  -- =========================================================
  process (CLK, RST_n) is
    variable vDx : unsigned(cW_MTL2_NBIT-1 downto 0);
    variable vDy : unsigned(cH_MTL2_NBIT-1 downto 0);
    variable vDist : unsigned(cH_NBIT-1 downto 0);
    variable vY_clipped : unsigned(cH_MTL2_NBIT-1 downto 0);
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s1_de <= '0';
      s1_dist_fact <= (others => '0');
      s1_morph_fact <= (others => '0');
      s1_valid <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s1_de <= DE_IN;
      -- If in visible area:
      -- 1) calculate the distance (diamond) and derive the
      -- glowing factor based on the distance between the current point and the
      -- touch;
      -- 2) calculate the glowing factor based on the y-coordinate of the touch
      if ( (DE_IN = '1') and (TOUCH_VALID = '1') ) then
        -- 1) distance factor
        -- X distance
        if (HPOS >= TOUCH_POS.x) then
          vDx := HPOS - TOUCH_POS.x;
        else
          vDx := TOUCH_POS.x - HPOS;
        end if;
        -- Y distance
        if (VPOS >= TOUCH_POS.y) then
          vDy := VPOS - TOUCH_POS.y;
        else
          vDy := TOUCH_POS.y - VPOS;
        end if;
        vDist := resize(vDx, cH_NBIT) + resize(vDy, cH_NBIT);
        if ( to_integer(vDist) < GLOW_RADIUS ) then
          s1_valid <= '1';
          if ( to_unsigned(255,8) < shift_left(vDist, GLOW_RADIUS_FACTOR) ) then
            s1_dist_fact <= (others => '0');
          else
            s1_dist_fact <= to_unsigned(255, 8) - resize(shift_left(vDist, GLOW_RADIUS_FACTOR), 8);
          end if;
        else
          s1_valid <= '0';
          s1_dist_fact <= (others => '0');
        end if;
        -- 2) y-coordinate factor
        if (TOUCH_POS.y < cY_CLIP_MIN) then
          vY_clipped := cY_CLIP_MIN;
        elsif (TOUCH_POS.y > cY_CLIP_MAX) then
          vY_clipped := cY_CLIP_MAX;
        else
          vY_clipped := TOUCH_POS.y;
        end if;
        s1_morph_fact <= to_unsigned(255, 8) - resize(shift_right(vY_clipped, MORPH_NBIT), 8);
      else
        s1_dist_fact <= (others => '0');
        s1_morph_fact <= (others => '0');
        s1_valid <= '0';
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Stage 2 - calculate the total glow factor as the product between morph
  --  and distance factors
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s2_de <= '0';
      s2_glow_fact <= (others => '0');
      s2_valid <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s2_de <= s1_de;
      s2_valid <= s1_valid;
      if (s1_valid = '1') then
        s2_glow_fact <= s1_morph_fact * s1_dist_fact;
      else
        s2_glow_fact <= (others => '0');
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  Stage 3 - Apply the glow
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
    variable tmp : unsigned(23 downto 0);
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      s3_de <= '0';
      s3_R_reg <= (others => '0');
      s3_G_reg <= (others => '0');
      s3_B_reg <= (others => '0');
--      s3_valid <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      s3_de <= s2_de;
--      s3_valid <= s2_valid;
      if (s2_valid = '1') then
        tmp := cTouchColor_array(IDX).R * s2_glow_fact;
        s3_R_reg <= tmp(23 downto 16);
        tmp := cTouchColor_array(IDX).G * s2_glow_fact;
        s3_G_reg <= tmp(23 downto 16);
        tmp := cTouchColor_array(IDX).B * s2_glow_fact;
        s3_B_reg <= tmp(23 downto 16);
      else
        s3_R_reg <= (others => '0');
        s3_G_reg <= (others => '0');
        s3_B_reg <= (others => '0');
      end if;
    end if;
  end process;

  R_OUT <= s3_R_reg;
  G_OUT <= s3_G_reg;
  B_OUT <= s3_B_reg;
  DE_OUT <= s3_de;

end architecture;
