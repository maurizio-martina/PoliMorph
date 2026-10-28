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
-- Title      : DDS synchronizer
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dds_synch.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the circuit to synchronize the DDS delta
-- phase generated @ 33 MHz with the DDS oscillator, which works @ 50 MHz. The
-- synchronization mechanism is based on toggle.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.mtl2_pkg.all;

entity dds_synch is
  port (
    -- ---- 33 MHz domain  ---------------
    CLK33           : in  std_logic;
    RST_n           : in  std_logic;
    MORPH_FACT_IN   : in unsigned(cH_MTL2_NBIT-1 downto 0);
    DDS_PHASE_IN    : in unsigned(23 downto 0);
    DDS_VALID_IN    : in  std_logic;
    -- ---- 50 MHz domain
    CLK50           : in  std_logic;
    MORPH_FACT_OUT  : out unsigned(cH_MTL2_NBIT-1 downto 0);
    DDS_PHASE_OUT   : out unsigned(23 downto 0);
    DDS_VALID_OUT   : out  std_logic
    );
end entity;

architecture rtl of dds_synch is

  signal sMorph_fact_reg : unsigned(cH_MTL2_NBIT-1 downto 0);
  signal sDDS_phase_reg : unsigned(23 downto 0);
  signal sDDS_valid_reg : std_logic;

  signal sUpdate33MHz : std_logic;
  signal sToggle33MHz : std_logic;

  signal sToggle50MHz_reg : std_logic_vector(2 downto 0);
  signal sUpdate50MHz : std_logic;

begin

  -----------------------------------------------------------------------------
  -- 33 MHz Domain
  -----------------------------------------------------------------------------
  -- input registers
  process (CLK33, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sMorph_fact_reg <= (others => '0');
      sDDS_phase_reg <= (others => '0');
      sDDS_valid_reg <= '0';
    elsif CLK33'event and CLK33 = '1' then  -- rising clock edge
      sMorph_fact_reg <= MORPH_FACT_IN;
      sDDS_phase_reg <= DDS_PHASE_IN;
      sDDS_valid_reg <= DDS_VALID_IN;
    end if;
  end process;

  -- registered change detector, when sUpdate33MHz goes to '1' _reg values are
  -- stable
  process (CLK33, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sUpdate33MHz <= '0';
    elsif CLK33'event and CLK33 = '1' then  -- rising clock edge
      if ( (sMorph_fact_reg /= MORPH_FACT_IN) or
           (sDDS_phase_reg /= DDS_PHASE_IN) or
           (sDDS_valid_reg  /= DDS_VALID_IN)
         ) then
        sUpdate33MHz <= '1';
      else
        sUpdate33MHz <= '0';
      end if;
    end if;
  end process;

  -- toggle synchronizer
  process (CLK33, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sToggle33MHz <= '0';
    elsif CLK33'event and CLK33 = '1' then  -- rising clock edge
      if (sUpdate33MHz = '1') then
        sToggle33MHz <= not(sToggle33MHz);
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- 50 MHz Domain: double FF
  -----------------------------------------------------------------------------
  process (CLK50, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      sToggle50MHz_reg <= (others => '0');
    elsif CLK50'event and CLK50 = '1' then  -- rising clock edge
      sToggle50MHz_reg(0) <= sToggle33MHz;
      sToggle50MHz_reg(2 downto 1) <= sToggle50MHz_reg(1 downto 0);
    end if;
  end process;

  -- update with XOR
  sUpdate50MHz <= sToggle50MHz_reg(2) xor sToggle50MHz_reg(1);

  -- output register
  process (CLK50, RST_n) is
  begin  -- process
    if RST_n = '0' then                 -- asynchronous reset (active low)
      MORPH_FACT_OUT <= (others => '0');
      DDS_PHASE_OUT <= (others => '0');
      DDS_VALID_OUT <= '0';
    elsif CLK50'event and CLK50 = '1' then  -- rising clock edge
      if (sUpdate50MHz = '1') then
        MORPH_FACT_OUT <= sMorph_fact_reg;
        DDS_PHASE_OUT <= sDDS_phase_reg;
        DDS_VALID_OUT <= sDDS_valid_reg;
      end if;
    end if;
  end process;

end architecture;
