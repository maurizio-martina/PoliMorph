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
-- Title      : Touch Interface
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : touch_interface.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the interface between the I2C touch config
-- module and the rest of the system. It contains toggle synchronizer to pass
-- from 50 MHz to 33 MHz.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;

entity touch_interface is
  port (
    CLK50           : in  std_logic;
    RST_n           : in  std_logic;
    -- Inputs generated @ 50 MHz by the I2C Touch Config module
    TOUCH_ARRAY_IN  : in  tTouchPosition;
    TOUCH_READY_IN  : in  std_logic;
    TOUCH_COUNT_IN  : in  unsigned(3 downto 0);
    CLK33           : in  std_logic;
    -- Outputs generated @ 33 MHz with a synthronization circuit
    TOUCH_ARRAY_OUT : out tTouchPosition;
    TOUCH_READY_OUT : out std_logic;
    TOUCH_COUNT_OUT : out unsigned(3 downto 0);
    TOUCH_ACK_IN    : in std_logic
    );
end entity;

architecture rtl of touch_interface is

  -- --------------------------------------------------------
  --  50 MHz domain: edge detection and hold register
  -- --------------------------------------------------------
  signal sReady_reg   : std_logic;
  signal sReady_pulse : std_logic;

  -- Hold registers + toggle
  signal sHold_position : tTouchPosition;
  signal sHold_count    : unsigned(3 downto 0);
  signal sHold_ready    : std_logic;
  signal sToggle_50     : std_logic;

  -- --------------------------------------------------------
  --  33 MHz domain synchronizers: double register on toggle
  -- --------------------------------------------------------
  signal sToggle_reg1, sToggle_reg2 : std_logic;
  signal sUpdate_33                 : std_logic;

begin

  -----------------------------------------------------------------------------
  -- 50 MHz Domain
  -----------------------------------------------------------------------------

  -- 1) Detect rising edge on TOUCH_READY
  -- past sample register
  process (CLK50, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sReady_reg <= '0';
    elsif CLK50'event and CLK50 = '1' then  -- rising clock edge
      sReady_reg <= TOUCH_READY_IN;
    end if;
  end process;

  -- edge detector
  sReady_pulse <= '1' when (TOUCH_READY_IN = '1' and sReady_reg = '0') else '0';

  -- 2) Hold register: sample coordinates and count on rising of TOUCH_READY
  -- and keeps valid till new touch event or watchdog rised
  process (CLK50, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sHold_position <= (others => (x => (others => '0'), y => (others => '0')));
      sHold_ready    <= '0';
      sHold_count    <= (others => '0');
      sToggle_50     <= '0';
    elsif CLK50'event and CLK50 = '1' then  -- rising clock edge
      if (sReady_pulse = '1') then
        sHold_position <= TOUCH_ARRAY_IN;
        sHold_ready <= '1';
        sHold_count <= TOUCH_COUNT_IN;
        sToggle_50  <= not(sToggle_50);
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  --  CDC: synchronizer from 50 MHz to 33 MHz
  --  two FFs and toggle
  -----------------------------------------------------------------------------
  process (CLK33, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sToggle_reg1 <= '0';
      sToggle_reg2 <= '0';
    elsif CLK33'event and CLK33 = '1' then  -- rising clock edge
      sToggle_reg1 <= sToggle_50;
      sToggle_reg2 <= sToggle_reg1;
    end if;
  end process;

  sUpdate_33 <= sToggle_reg1 xor sToggle_reg2;

  -----------------------------------------------------------------------------
  -- 33 MHz domain: sample when sUpdate_33 = '1'
  -- data hold_* are already stable when sUpdate_33 = '1'
  -----------------------------------------------------------------------------
  process (CLK33, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      TOUCH_ARRAY_OUT <= (others => (x => (others => '0'), y => (others => '0')));
      TOUCH_READY_OUT <= '0';
      TOUCH_COUNT_OUT <= (others => '0');
    elsif CLK33'event and CLK33 = '1' then  -- rising clock edge
      if (sUpdate_33 = '1') then
        TOUCH_ARRAY_OUT <= sHold_position;
        TOUCH_READY_OUT <= sHold_ready;
        TOUCH_COUNT_OUT <= sHold_count;
      elsif (TOUCH_ACK_IN = '1') then
        TOUCH_READY_OUT <= '0';
      end if;
    end if;
  end process;

end architecture;
