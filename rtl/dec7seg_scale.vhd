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
-- Title      : Three 7 segment decoders to show scale names
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dec7seg_scale.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-26
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of three 7 segment decoders
-- display the name of the scales
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

library work;
use work.notes_pkg.all;

entity dec7seg_scale is
  port (
    SW_SCALE : in  std_logic_vector(3 downto 0);
    DOUT0    : out std_logic_vector(0 to 6);
    DOUT1    : out std_logic_vector(0 to 6);
    DOUT2    : out std_logic_vector(0 to 6));
end entity dec7seg_scale;

architecture beh of dec7seg_scale is

begin  -- architecture beh

  process (SW_SCALE) is
  begin  -- process
    case to_integer(unsigned(SW_SCALE)) is
--      when cTONIC_POS =>
      when cMINOR_NAT_POS =>            -- MIN
        DOUT0 <= "1101010";
        DOUT1 <= "1001111";
        DOUT2 <= "0101010";
      when cMAJOR_POS =>                -- MAJ
        DOUT0 <= "1000011";
        DOUT1 <= "0001000";
        DOUT2 <= "0101010";
      when cDORIAN_POS =>               -- DOr
        DOUT0 <= "1111010";
        DOUT1 <= "0000001";
        DOUT2 <= "1000010";
      when cPHRYGIAN_POS =>             -- PHr
        DOUT0 <= "1111010";
        DOUT1 <= "1101000";
        DOUT2 <= "0011000";
      when cLYDIAN_POS =>               -- LYd
        DOUT0 <= "1000010";
        DOUT1 <= "1000100";
        DOUT2 <= "1110001";
      when cMIXOLYDIAN_POS =>           -- MIX
        DOUT0 <= "1001001";
        DOUT1 <= "1001111";
        DOUT2 <= "0101010";
      when cLOCRIAN_POS =>              -- LOC
        DOUT0 <= "0110001";
        DOUT1 <= "0000001";
        DOUT2 <= "1110001";
      when cPENTATONIC_MAJ_POS =>       -- PMJ
        DOUT0 <= "1000011";
        DOUT1 <= "0101010";
        DOUT2 <= "0011000";
      when cPENTATONIC_MIN_POS =>       -- PMn
        DOUT0 <= "1101010";
        DOUT1 <= "0101010";
        DOUT2 <= "0011000";
      when cBLUES_POS =>                -- BLU
        DOUT0 <= "1000001";
        DOUT1 <= "1110001";
        DOUT2 <= "1100000";
      when cWHOLE_TONE_POS =>           -- Wt
        DOUT0 <= "1111111";
        DOUT1 <= "1110000";
        DOUT2 <= "1010101";
      when cDIMINISHED_TS_POS =>        -- dtS
        DOUT0 <= "0100100";
        DOUT1 <= "1110000";
        DOUT2 <= "1000010";
      when cDIMINISHED_ST_POS =>        -- dSt
        DOUT0 <= "1110000";
        DOUT1 <= "0100100";
        DOUT2 <= "1000010";
      when cARABIAN_POS =>              -- ArA
        DOUT0 <= "0001000";
        DOUT1 <= "1111010";
        DOUT2 <= "0001000";
      when cCHROMATIC_POS =>            -- CHr
        DOUT0 <= "1111010";
        DOUT1 <= "1001000";
        DOUT2 <= "0110001";
      when others =>                    -- default to TONIC (TOn)
        DOUT0 <= "1101010";
        DOUT1 <= "0000001";
        DOUT2 <= "1110000";
    end case;
  end process;

end architecture beh;
