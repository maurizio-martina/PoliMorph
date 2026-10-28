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
-- Title      : Touch Manager
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : touch_manager.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the logic to implement touch tracking and to
-- generate a valid pulse representing the duration of each touch. Every time
-- TOUCH_READY_IN goes to '1' an edge detector generates a one-clock-cycle
-- pulse that enables a watch-dog counter. A new pulse clears the watch-dog
-- counter. If the systems is not receiving a new pulse for 50 ms, then the
-- watch-dog terminal count is used to state "no touch". The tracking is
-- implemented locking touches to oscillators and checking new touch positions. If
-- a touch is locked to an oscillator and the new position of this touch is
-- close enough to the previous one, then the touch is kept locked to the same
-- oscillator.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;

entity touch_manager is
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
end entity touch_manager;

architecture beh of touch_manager is

  constant cNBIT_WD : integer := 21;
  -- 50 ms watchdog threshold @ 33 MHz
  constant cWD_THR  : integer := 1666667;

  constant cD_THR : unsigned(cW_MTL2_NBIT-1 downto 0) := to_unsigned(64, cW_MTL2_NBIT);

  type tState is (IDLES_S, S0_S, S1_S, S2_S, S3_S, S4_S, LAST_S, OFF_S);

  signal sTouchReady_reg   : std_logic;
  signal sTouchReady_pulse : std_logic;

  signal sWatchDog_cnt    : unsigned(cNBIT_WD-1 downto 0);
  signal sWatchDog_cnt_en : std_logic;
  signal sWatchDog_cnt_tc : std_logic;

  signal sDeactivateOscillators : std_logic;

  signal sTouchCnt_reg : unsigned(3 downto 0);
  signal sTouchPosition_reg : tTouchPosition;

  signal sState : tState;
  signal sUpdateOscillators : std_logic;
  signal sAllocateOscillators : std_logic;
  signal sDeactivateOscillators_ack : std_logic;

  signal sTouchDistance_min : unsigned(cW_MTL2_NBIT-1 downto 0);
  signal sCurrentMin : integer range 0 to cN_MTL2_TOUCH-1;

  signal sTouchLocked : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);
  signal sOscillators : tTouchPosition;

  signal sCurrentOscillator : integer range 0 to cN_MTL2_TOUCH-1;
  signal sTouchPositionOut : tTouchPosition;
  signal sTouchValidOut : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);

begin  -- architecture beh

  -----------------------------------------------------------------------------
  -- detect valid touch
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sTouchReady_reg <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      sTouchReady_reg <= TOUCH_READY_IN;
    end if;
  end process;

  sTouchReady_pulse <= '1' when (TOUCH_READY_IN = '1' and sTouchReady_reg = '0') else '0';
  TOUCH_ACK_OUT <= sTouchReady_pulse;

  -----------------------------------------------------------------------------
  -- watchdog
  -----------------------------------------------------------------------------

  -- watchdog enable
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sWatchDog_cnt_en <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sTouchReady_pulse = '1') then
        sWatchDog_cnt_en <= '1';
      elsif (sWatchDog_cnt_tc = '1') then
        sWatchDog_cnt_en <= '0';
      end if;
    end if;
  end process;

  -- watchdog counter
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sWatchDog_cnt <= (others => '0');
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sWatchDog_cnt_en = '1') then
        if ((sWatchDog_cnt_tc = '1') or (sTouchReady_pulse = '1')) then
          sWatchDog_cnt <= (others => '0');
        else
          sWatchDog_cnt <= sWatchDog_cnt + 1;
        end if;
      end if;
    end if;
  end process;

  -- watchdog terminal count
  sWatchDog_cnt_tc <= '1' when (sWatchDog_cnt = to_unsigned(cWD_THR, cNBIT_WD)) else '0';

  -- Deactivate oscillators flag
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                     -- asynchronous reset (active low)
      sDeactivateOscillators <= '0';
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sTouchReady_pulse = '1') then
        sDeactivateOscillators <= '0';
      elsif (sWatchDog_cnt_tc = '1') then
        sDeactivateOscillators <= '1';
      elsif (sDeactivateOscillators_ack = '1') then
        sDeactivateOscillators <= '0';
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- registers: touch pulse acts as load; the watch-dog terminal count resets
  -- the touch count register
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sTouchCnt_reg <= (others => '0');
      sTouchPosition_reg <= (others => (x => (others => '0'), y => (others => '0')));
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sTouchReady_pulse = '1') then
        sTouchCnt_reg <= TOUCH_CNT_IN;
        sTouchPosition_reg <= TOUCH_POSITION_IN;
      elsif (sWatchDog_cnt_tc = '1') then
        sTouchCnt_reg <= (others => '0');
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- FSM to manage touch: IDLE, one-state-per-touch (SX_S) to update the sound
  -- oscillators, one state to allocate free oscillators (LAST_S), one state to
  -- turn off oscillators (OFF_S)
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sState <= IDLES_S;
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      case sState is
        when IDLES_S =>
          if (sTouchReady_pulse = '1') then
            sState <= S0_S;
          elsif (sDeactivateOscillators = '1') then
            sState <= OFF_S;
          end if;
        when S0_S =>
          sState <= S1_S;
        when S1_S =>
          sState <= S2_S;
        when S2_S =>
          sState <= S3_S;
        when S3_S =>
          sState <= S4_S;
        when S4_S =>
          sState <= LAST_S;
        when LAST_S | OFF_S =>
          sState <= IDLES_S;
        when others =>
          sState <= IDLES_S;
      end case;
    end if;
  end process;

  process (sState) is
  begin  -- process
    case sState is
      when IDLES_S =>
        sUpdateOscillators <= '0';
        sCurrentOscillator <= 0;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when S0_S =>
        sUpdateOscillators <= '1';
        sCurrentOscillator <= 0;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when S1_S =>
        sUpdateOscillators <= '1';
        sCurrentOscillator <= 1;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when S2_S =>
        sUpdateOscillators <= '1';
        sCurrentOscillator <= 2;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when S3_S =>
        sUpdateOscillators <= '1';
        sCurrentOscillator <= 3;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when S4_S =>
        sUpdateOscillators <= '1';
        sCurrentOscillator <= 4;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
      when LAST_S =>
        sUpdateOscillators <= '0';
        sCurrentOscillator <= 0;
        sAllocateOscillators <= '1';
        sDeactivateOscillators_ack <= '0';
      when OFF_S =>
        sUpdateOscillators <= '0';
        sCurrentOscillator <= 0;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '1';
      when others =>
        sUpdateOscillators <= '0';
        sCurrentOscillator <= 0;
        sAllocateOscillators <= '0';
        sDeactivateOscillators_ack <= '0';
    end case;
  end process;

  -----------------------------------------------------------------------------
  -- given the current oscillator (from FSM) compares the position (X/Y) of current
  -- oscillator with all the active touch positions (X/Y)
  process (sTouchPosition_reg, sOscillators, sCurrentOscillator, sTouchCnt_reg, sTouchLocked) is
    variable vAx : unsigned(cW_MTL2_NBIT-1 downto 0);
    variable vBx : unsigned(cW_MTL2_NBIT-1 downto 0);
    variable vAy : unsigned(cH_MTL2_NBIT-1 downto 0);
    variable vBy : unsigned(cH_MTL2_NBIT-1 downto 0);
    variable vDx : unsigned(cW_MTL2_NBIT-1 downto 0);
    variable vDy : unsigned(cH_MTL2_NBIT-1 downto 0);
    variable vD : unsigned(cW_MTL2_NBIT downto 0);
    variable vM : unsigned(cW_MTL2_NBIT-1 downto 0);
    variable vMpos : integer range 0 to cN_MTL2_TOUCH-1;
    constant cDmax : unsigned(cW_MTL2_NBIT downto 0) := (cW_MTL2_NBIT => '0', others => '1');
  begin  -- process
    -- Initialize A and B
    if (sTouchCnt_reg > 0) then
      vAx := sOscillators(sCurrentOscillator).x;
      vBx := sTouchPosition_reg(0).x;
      vAy := sOscillators(sCurrentOscillator).y;
      vBy := sTouchPosition_reg(0).y;
    else
      vAx := (others => '1');
      vBx := (others => '0');
      vAy := (others => '1');
      vBy := (others => '0');
    end if;
    -- Calculate X distance
    if (vAx < vBx) then
      vDx := vBx - vAx;
    else
      vDx := vAx - vBx;
    end if;
    -- Calculate Y distance
    if (vAy < vBy) then
      vDy := vBy - vAy;
    else
      vDy := vAy - vBy;
    end if;
    -- Calculate Manhattan distance and compare with maximum possible
    vD := resize(vDx, cW_MTL2_NBIT+1)+resize(vDy, cW_MTL2_NBIT+1);
    if (vD > cDmax) then
      vD := cDmax;
    end if;
    -- If the first touch is not locked to any oscillator, then initialize the
    -- maximum distance search with current distance, otherwise set it to
    -- maximum possible
    if (sTouchLocked(0) = '0') then
      vM := vD(cW_MTL2_NBIT-1 downto 0);
    else
      vM := cDmax(cW_MTL2_NBIT-1 downto 0);
    end if;
    vMpos := 0;
    -- Search for minimum distance between current oscillator and active touches
    for idx in 1 to cN_MTL2_TOUCH-1 loop
      if (to_integer(sTouchCnt_reg) >= (idx+1)) then
        vBx := sTouchPosition_reg(idx).x;
        vBy := sTouchPosition_reg(idx).y;
        if (vAx < vBx) then
          vDx := vBx - vAx;
        else
          vDx := vAx - vBx;
        end if;
        if (vAy < vBy) then
          vDy := vBy - vAy;
        else
          vDy := vAy - vBy;
        end if;
        vD := resize(vDx, cW_MTL2_NBIT+1)+resize(vDy, cW_MTL2_NBIT+1);
        if (vD > cDmax) then
          vD := cDmax;
        end if;
        if ( (vD(cW_MTL2_NBIT-1 downto 0) < vM) and (sTouchLocked(idx) = '0') ) then
          vM := vD(cW_MTL2_NBIT-1 downto 0);
          vMpos := idx;
        end if;
      end if;
    end loop;  -- idx
    sTouchDistance_min <= vM;
    sCurrentMin <= vMpos;
  end process;

  -----------------------------------------------------------------------------
  -- registers to record touch locked to oscillators and valid out of each oscillator
  -----------------------------------------------------------------------------
  process (CLK, RST_n) is
    variable vTouchLocked : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);
    variable vTouchValidOut : std_logic_vector(cN_MTL2_TOUCH-1 downto 0);
    variable vOscillators : tTouchPosition;
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sTouchLocked <= (others => '0');
      sTouchValidOut <= (others => '0');
      sOscillators <= (others => (x => (others => '0'), y => (others => '0')));
    elsif CLK'event and CLK = '1' then  -- rising clock edge
      if (sTouchReady_pulse = '1') then
        sTouchLocked <= (others => '0');
      else
        if (sUpdateOscillators = '1') then
          -- If current oscillator is active and touch with minimum distance
          -- from it is not locked, lock it
          if ( (sTouchValidOut(sCurrentOscillator) = '1') and (sTouchDistance_min < cD_THR) and (sTouchLocked(sCurrentMin) = '0') ) then
            sTouchLocked(sCurrentMin) <= '1';
            sTouchValidOut(sCurrentOscillator) <= '1';
            sOscillators(sCurrentOscillator) <= sTouchPosition_reg(sCurrentMin);
          else
            -- else disable it
            sTouchValidOut(sCurrentOscillator) <= '0';
            sOscillators(sCurrentOscillator).x <= (others => '0');
            sOscillators(sCurrentOscillator).y <= (others => '0');
          end if;
        elsif (sAllocateOscillators = '1') then
          -- check for touches not locked to be allocated to free oscillators
          vTouchLocked := sTouchLocked;
          vTouchValidOut := sTouchValidOut;
          vOscillators := sOscillators;
          for idx in 0 to cN_MTL2_TOUCH-1 loop
            for jdx in 0 to cN_MTL2_TOUCH-1 loop
              if ( (to_integer(sTouchCnt_reg) >= (idx+1)) and (vTouchLocked(idx) = '0') and (vTouchValidOut(jdx) = '0') ) then
                vTouchLocked(idx) := '1';
                vTouchValidOut(jdx) := '1';
                vOscillators(jdx) := sTouchPosition_reg(idx);
              end if;
            end loop;  -- jdx
          end loop;  -- idx
          sTouchLocked <= vTouchLocked;
          sTouchValidOut <= vTouchValidOut;
          sOscillators <= vOscillators;
        elsif (sDeactivateOscillators_ack = '1') then
          -- if the FSM is acknowledgin a deactivation request, then clear all
          sTouchLocked <= (others => '0');
          sTouchValidOut <= (others => '0');
          sOscillators <= (others => (x => (others => '0'), y => (others => '0')));
        end if;
      end if;
    end if;
  end process;

  TOUCH_CNT_OUT <= sTouchCnt_reg;
  TOUCH_POSITION_OUT <= sOscillators;
  TOUCH_VALID_OUT <= sTouchValidOut;

end architecture beh;
