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
-- Title      : Hexadecimal 7 segment decoder
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dec7seg_hex.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-26
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of an hexadecimal 7
-- segment decoder
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity dec7seg_hex is
  port (
    DIN  : in  std_logic_vector(3 downto 0);
    DOUT : out std_logic_vector(0 to 6));
end entity dec7seg_hex;

architecture beh of dec7seg_hex is

begin  -- architecture beh

  process (DIN) is
  begin  -- process
    case to_integer(unsigned(DIN)) is
      when 0 =>
        DOUT <= "0000001";
      when 1 =>
        DOUT <= "1001111";
      when 2 =>
        DOUT <= "0010010";
      when 3 =>
        DOUT <= "0000110";
      when 4 =>
        DOUT <= "1001100";
      when 5 =>
        DOUT <= "0100100";
      when 6 =>
        DOUT <= "0100000";
      when 7 =>
        DOUT <= "0001111";
      when 8 =>
        DOUT <= "0000000";
      when 9 =>
        DOUT <= "0001100";
      when 10 =>
        DOUT <= "0001000";
      when 11 =>
        DOUT <= "1100000";
      when 12 =>
        DOUT <= "0110001";
      when 13 =>
        DOUT <= "1000010";
      when 14 =>
        DOUT <= "0110000";
      when 15 =>
        DOUT <= "0111000";
      when others =>
        DOUT <= "1111111";
    end case;
  end process;

end architecture beh;
