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
-- Title      : Unlock/Lock 7 segment decoder
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : dec7seg_lock.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-26
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the implementation of a 7 segment decoder to
-- display U (Unlock) or L (Lock)
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity dec7seg_lock is
  port (
    PITCH_LOCKED : in  std_logic;
    HEX        : out std_logic_vector(0 to 6));
end entity dec7seg_lock;

architecture beh of dec7seg_lock is

begin  -- architecture beh

  HEX <= "1000001" when (PITCH_LOCKED = '0') else "1110001";

end architecture beh;
