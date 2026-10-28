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
-- Title      : MTL2 package
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : mtl2_pkg.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-16
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the package with constants related to
-- resolution, timing and characteristics of the MTL2 board/touch-screen
-------------------------------------------------------------------------------
library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

package mtl2_pkg is

  -----------------------------------------------------------------------------
  -- specifications for MTL2 (800x480) pixel at 33 MHz
  -----------------------------------------------------------------------------
  -- Resolution
  constant cW_MTL2 : integer := 800;
  constant cH_MTL2 : integer := 480;
  constant cW_MTL2_NBIT : integer := 10;
  constant cH_MTL2_NBIT : integer := 9;
  -- Horizontal timing
  constant cH_PULSE_MTL2 : integer := 20;
  constant cH_BACK_PORCH_MTL2 : integer := 46;
  constant cH_FORW_PORCH_MTL2 : integer := 210;
  -- Vertical timing
  constant cV_PULSE_MTL2 : integer := 10;
  constant cV_BACK_PORCH_MTL2 : integer := 23;
  constant cV_FORW_PORCH_MTL2 : integer := 22;
  -- Horizontal/Veritcal counters bitwidth
  constant cH_NBIT : integer := 11;
  constant cV_NBIT : integer := 10;

  -- NOT USED
  -- constant cTouchGesture_MoveUp : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#10#,8));
  -- constant cTouchGesture_MoveLeft : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#14#,8));
  -- constant cTouchGesture_MoveDown : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#18#,8));
  -- constant cTouchGesture_MoveRight : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#1C#,8));
  -- constant cTouchGesture_ZoomIn : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#48#,8));
  -- constant cTouchGesture_ZoomOut : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#49#,8));
  -- constant cTouchGesture_NoGesture : std_logic_vector(7 downto 0) := std_logic_vector(to_unsigned(16#00#,8));

  -----------------------------------------------------------------------------
  -- Design constants
  -----------------------------------------------------------------------------
  constant cW : integer := cW_MTL2;
  constant cH : integer := cH_MTL2;

  constant cH_PULSE : integer := cH_PULSE_MTL2;
  constant cH_BACK_PORCH : integer := cH_BACK_PORCH_MTL2;
  constant cH_FORW_PORCH : integer := cH_FORW_PORCH_MTL2;

  constant cV_PULSE : integer := cV_PULSE_MTL2;
  constant cV_BACK_PORCH : integer := cV_BACK_PORCH_MTL2;
  constant cV_FORW_PORCH : integer := cV_FORW_PORCH_MTL2;

  -- horizontal counter thresholds
  constant cH_THR1 : integer := cH_PULSE;
  constant cH_THR2 : integer := cH_BACK_PORCH;
  constant cH_THR3 : integer := cH_THR2 + cW;
  constant cH_TC : integer := cH_THR3 + cH_FORW_PORCH - 1;

  -- vertical counter thresholds
  constant cV_THR1 : integer := cV_PULSE;
  constant cV_THR2 : integer := cV_BACK_PORCH;
  constant cV_THR3 : integer := cV_THR2 + cH;
  constant cV_TC : integer := cV_THR3 + cV_FORW_PORCH - 1;

  -----------------------------------------------------------------------------
  -- Touch record and array
  -----------------------------------------------------------------------------

  constant cN_MTL2_TOUCH : integer := 5;

  type rTouchPosition is record
    x : unsigned(cW_MTL2_NBIT-1 downto 0);
    y : unsigned(cH_MTL2_NBIT-1 downto 0);
  end record rTouchPosition;

  type tTouchPosition is array (0 to cN_MTL2_TOUCH-1) of rTouchPosition;

end package mtl2_pkg;
