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
-- Title      : Audio PLL
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : pll_audio.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2026-10-27
-- Last update: 2026-10-27
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: PLL generating the 12.288 MHz master clock (AUD_XCK) of the
-- WM8731 audio codec from the 50 MHz board clock. Fractional-N mode:
-- 12.288 MHz has no exact integer ratio with 50 MHz.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

library altera_lnsim;
use altera_lnsim.altera_lnsim_components.all;

entity pll_audio is
  port (
    refclk   : in  std_logic := '0';   
    rst      : in  std_logic := '0';   
    outclk_0 : out std_logic;          
    locked   : out std_logic           
    );
end entity pll_audio;

architecture rtl of pll_audio is

  signal s_outclk : std_logic_vector(0 downto 0);

begin

  altera_pll_i : altera_pll
    generic map (
      fractional_vco_multiplier => "true",
      reference_clock_frequency => "50.0 MHz",
      operation_mode            => "direct",
      number_of_clocks          => 1,
      output_clock_frequency0   => "12.288000 MHz",
      phase_shift0              => "0 ps",
      duty_cycle0               => 50,
      output_clock_frequency1   => "0 MHz",
      phase_shift1              => "0 ps",
      duty_cycle1               => 50,
      output_clock_frequency2   => "0 MHz",
      phase_shift2              => "0 ps",
      duty_cycle2               => 50,
      output_clock_frequency3   => "0 MHz",
      phase_shift3              => "0 ps",
      duty_cycle3               => 50,
      output_clock_frequency4   => "0 MHz",
      phase_shift4              => "0 ps",
      duty_cycle4               => 50,
      output_clock_frequency5   => "0 MHz",
      phase_shift5              => "0 ps",
      duty_cycle5               => 50,
      output_clock_frequency6   => "0 MHz",
      phase_shift6              => "0 ps",
      duty_cycle6               => 50,
      output_clock_frequency7   => "0 MHz",
      phase_shift7              => "0 ps",
      duty_cycle7               => 50,
      output_clock_frequency8   => "0 MHz",
      phase_shift8              => "0 ps",
      duty_cycle8               => 50,
      output_clock_frequency9   => "0 MHz",
      phase_shift9              => "0 ps",
      duty_cycle9               => 50,
      output_clock_frequency10  => "0 MHz",
      phase_shift10             => "0 ps",
      duty_cycle10              => 50,
      output_clock_frequency11  => "0 MHz",
      phase_shift11             => "0 ps",
      duty_cycle11              => 50,
      output_clock_frequency12  => "0 MHz",
      phase_shift12             => "0 ps",
      duty_cycle12              => 50,
      output_clock_frequency13  => "0 MHz",
      phase_shift13             => "0 ps",
      duty_cycle13              => 50,
      output_clock_frequency14  => "0 MHz",
      phase_shift14             => "0 ps",
      duty_cycle14              => 50,
      output_clock_frequency15  => "0 MHz",
      phase_shift15             => "0 ps",
      duty_cycle15              => 50,
      output_clock_frequency16  => "0 MHz",
      phase_shift16             => "0 ps",
      duty_cycle16              => 50,
      output_clock_frequency17  => "0 MHz",
      phase_shift17             => "0 ps",
      duty_cycle17              => 50,
      pll_type                  => "General",
      pll_subtype               => "General"
      )
    port map (
      rst      => rst,
      outclk   => s_outclk,
      locked   => locked,
      fboutclk => open,
      fbclk    => '0',
      refclk   => refclk
      );

  outclk_0 <= s_outclk(0);

end architecture rtl;
