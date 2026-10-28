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
-- Title      : WM8731 I2C configuration sequencer
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : wm8731_i2c_cfg.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-23
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains the I2C configuration sequencer for the WM8731 audio codec.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wm8731_i2c_cfg is
  port (
    CLK      : in    std_logic;
    RST_n    : in    std_logic;
    I2C_SCL  : out   std_logic;
    I2C_SDA  : inout std_logic;
    CFG_DONE : out   std_logic
  );
end entity wm8731_i2c_cfg;

architecture rtl of wm8731_i2c_cfg is

  constant cNUM_REGS : integer := 11;

  type t_cfg_rom is array (0 to cNUM_REGS-1) of
    std_logic_vector(15 downto 0);

  constant cCFG_ROM : t_cfg_rom := (
    x"1E00",   -- R15 reset
    x"0C20",   -- R6  power  (OSCPD=1, all else on)
    x"001A",   -- R0  left  line in  (vol=0x1A about +2 dB, no mute)
    x"021A",   -- R1  right line in
    x"047B",   -- R2  left  headphone out (0x7B about +2 dB, LZCEN=0)
    x"067B",   -- R3  right headphone out
    x"0895",   -- R4  analogue path  (DACSEL=1, MIC in, MICBOOST=+20dB)
    x"0A06",   -- R5  digital path   (DEEMPH=01, ADCHPD=1)
    x"0E49",   -- R7  interface      (MASTER, 24-bit, LEFT-JUSTIFIED)
    x"1000",   -- R8  sampling       (Normal, 12.288 MHz, 48 kHz, BOSR=0)
    x"1201"    -- R9  activate
  );

  -- ----------------------------------------------------------
  -- Timing
  -- ----------------------------------------------------------
  constant cHALF      : integer := 249;     -- 250 x 20 ns = 5 us -> 100 kHz
  constant cPWR_DELAY : integer := 499_999; -- 10 ms at 50 MHz

  -- Steps per transaction (0 .. cSTEPS):
  --   0        : bus idle (1 half-period before START)
  --   1-2      : START condition  (SDA falls, SCL falls)
  --   3-18     : device addr 0x34 (8 bits x 2 half-periods)
  --   19-20    : ACK 1
  --   21-36    : data byte 1 (8 bits x 2)
  --   37-38    : ACK 2
  --   39-54    : data byte 2 (8 bits x 2)
  --   55-56    : ACK 3
  --   57       : SCL falls  (SDA still HIGH)
  --   58       : SDA driven LOW
  --   59       : SCL rises  (SDA LOW - STOP setup)
  --   60       : SDA released HIGH -> STOP condition
  constant cSTEPS : integer := 60;

  -- ----------------------------------------------------------
  -- FSM
  -- ----------------------------------------------------------
  type t_state is (sIDLE, sWAIT, sRUN, sDONE);
  signal state    : t_state := sIDLE;

  signal pwr_cnt  : integer range 0 to cPWR_DELAY := 0;
  signal tick_cnt : integer range 0 to cHALF      := 0;
  signal mu_cnt   : integer range 0 to cSTEPS := 0;
  signal reg_idx  : integer range 0 to cNUM_REGS  := 0;
  signal tick     : std_logic;

  signal cfg_word : std_logic_vector(15 downto 0);

  signal scl_c   : std_logic;
  signal sda_drv : std_logic;  -- '1' = pull SDA low (open-drain)

  signal scl_reg : std_logic;
  signal sda_reg : std_logic;

begin

  cfg_word <= cCFG_ROM(reg_idx) when reg_idx < cNUM_REGS
              else (others => '0');

  p_out_reg : process (CLK, RST_n) begin
    if RST_n = '0' then
      scl_reg <= '1';
      sda_reg <= '0';
    elsif rising_edge(CLK) then
      scl_reg <= scl_c;
      sda_reg <= sda_drv;
    end if;
  end process p_out_reg;

  I2C_SCL  <= scl_reg;
  I2C_SDA  <= '0' when sda_reg = '1' else 'Z';
  CFG_DONE <= '1' when state = sDONE else '0';

  -- ----------------------------------------------------------
  -- Half-period tick
  -- ----------------------------------------------------------
  process (CLK, RST_n) begin
    if RST_n = '0' then
      tick_cnt <= 0; tick <= '0';
    elsif rising_edge(CLK) then
      tick <= '0';
      if state = sRUN then
        if tick_cnt = cHALF then
          tick_cnt <= 0; tick <= '1';
        else
          tick_cnt <= tick_cnt + 1;
        end if;
      else
        tick_cnt <= 0;
      end if;
    end if;
  end process;

  -- ----------------------------------------------------------
  -- Main sequencer FSM
  -- ----------------------------------------------------------
  process (CLK, RST_n) begin
    if RST_n = '0' then
      state   <= sIDLE;
      pwr_cnt <= 0;
      mu_cnt  <= 0;
      reg_idx <= 0;
    elsif rising_edge(CLK) then
      case state is
        when sIDLE =>
          pwr_cnt <= 0;
          state   <= sWAIT;

        when sWAIT =>
          if pwr_cnt = cPWR_DELAY then
            mu_cnt <= 0; reg_idx <= 0; state <= sRUN;
          else
            pwr_cnt <= pwr_cnt + 1;
          end if;

        when sRUN =>
          if tick = '1' then
            if mu_cnt = cSTEPS then
              mu_cnt <= 0;
              if reg_idx = cNUM_REGS - 1 then
                state <= sDONE;
              else
                reg_idx <= reg_idx + 1;
              end if;
            else
              mu_cnt <= mu_cnt + 1;
            end if;
          end if;

        when sDONE => null;
      end case;
    end if;
  end process;

  -- ----------------------------------------------------------
  -- Combinatorial I2C bit generator
  --
  -- sda_drv = '1'  -> drive SDA LOW  (open-drain asserted)
  -- sda_drv = '0'  -> release SDA    (pulled HIGH externally)
  --
  -- For a data bit b:  sda_drv = NOT b
  --   b='0' -> sda_drv='1' (pull low)
  --   b='1' -> sda_drv='0' (release high)
  --
  -- Device address 0x34 = 0011_0100 MSB-first:
  --   b7=0, b6=0, b5=1, b4=1, b3=0, b2=1, b1=0, b0=0
  -- ----------------------------------------------------------
  process (state, mu_cnt, cfg_word) begin
    scl_c   <= '1';
    sda_drv <= '0';   -- bus idle default

    if state = sRUN then
      case mu_cnt is

        -- ---- Idle + START condition -------------------------
        when 0  => scl_c <= '1'; sda_drv <= '0';  -- bus idle (SDA high)
        when 1  => scl_c <= '1'; sda_drv <= '1';  -- SDA falls -> START
        when 2  => scl_c <= '0'; sda_drv <= '1';  -- SCL falls

        -- ---- Device address 0x34 = 0011_0100 ---------------
        -- bit 7 = 0
        when 3  => scl_c <= '0'; sda_drv <= '1';
        when 4  => scl_c <= '1'; sda_drv <= '1';
        -- bit 6 = 0
        when 5  => scl_c <= '0'; sda_drv <= '1';
        when 6  => scl_c <= '1'; sda_drv <= '1';
        -- bit 5 = 1
        when 7  => scl_c <= '0'; sda_drv <= '0';
        when 8  => scl_c <= '1'; sda_drv <= '0';
        -- bit 4 = 1
        when 9  => scl_c <= '0'; sda_drv <= '0';
        when 10 => scl_c <= '1'; sda_drv <= '0';
        -- bit 3 = 0
        when 11 => scl_c <= '0'; sda_drv <= '1';
        when 12 => scl_c <= '1'; sda_drv <= '1';
        -- bit 2 = 1
        when 13 => scl_c <= '0'; sda_drv <= '0';
        when 14 => scl_c <= '1'; sda_drv <= '0';
        -- bit 1 = 0
        when 15 => scl_c <= '0'; sda_drv <= '1';
        when 16 => scl_c <= '1'; sda_drv <= '1';
        -- bit 0 = 0  (R/W=0 = Write)
        when 17 => scl_c <= '0'; sda_drv <= '1';
        when 18 => scl_c <= '1'; sda_drv <= '1';

        -- ---- ACK 1  (release SDA, WM8731 may pull low) -----
        when 19 => scl_c <= '0'; sda_drv <= '0';
        when 20 => scl_c <= '1'; sda_drv <= '0';

        -- ---- Data byte 1 = cfg_word[15:8]  MSB first -------
        when 21 => scl_c <= '0'; sda_drv <= not cfg_word(15);
        when 22 => scl_c <= '1'; sda_drv <= not cfg_word(15);
        when 23 => scl_c <= '0'; sda_drv <= not cfg_word(14);
        when 24 => scl_c <= '1'; sda_drv <= not cfg_word(14);
        when 25 => scl_c <= '0'; sda_drv <= not cfg_word(13);
        when 26 => scl_c <= '1'; sda_drv <= not cfg_word(13);
        when 27 => scl_c <= '0'; sda_drv <= not cfg_word(12);
        when 28 => scl_c <= '1'; sda_drv <= not cfg_word(12);
        when 29 => scl_c <= '0'; sda_drv <= not cfg_word(11);
        when 30 => scl_c <= '1'; sda_drv <= not cfg_word(11);
        when 31 => scl_c <= '0'; sda_drv <= not cfg_word(10);
        when 32 => scl_c <= '1'; sda_drv <= not cfg_word(10);
        when 33 => scl_c <= '0'; sda_drv <= not cfg_word(9);
        when 34 => scl_c <= '1'; sda_drv <= not cfg_word(9);
        when 35 => scl_c <= '0'; sda_drv <= not cfg_word(8);
        when 36 => scl_c <= '1'; sda_drv <= not cfg_word(8);

        -- ---- ACK 2 ------------------------------------------
        when 37 => scl_c <= '0'; sda_drv <= '0';
        when 38 => scl_c <= '1'; sda_drv <= '0';

        -- ---- Data byte 2 = cfg_word[7:0]  MSB first --------
        when 39 => scl_c <= '0'; sda_drv <= not cfg_word(7);
        when 40 => scl_c <= '1'; sda_drv <= not cfg_word(7);
        when 41 => scl_c <= '0'; sda_drv <= not cfg_word(6);
        when 42 => scl_c <= '1'; sda_drv <= not cfg_word(6);
        when 43 => scl_c <= '0'; sda_drv <= not cfg_word(5);
        when 44 => scl_c <= '1'; sda_drv <= not cfg_word(5);
        when 45 => scl_c <= '0'; sda_drv <= not cfg_word(4);
        when 46 => scl_c <= '1'; sda_drv <= not cfg_word(4);
        when 47 => scl_c <= '0'; sda_drv <= not cfg_word(3);
        when 48 => scl_c <= '1'; sda_drv <= not cfg_word(3);
        when 49 => scl_c <= '0'; sda_drv <= not cfg_word(2);
        when 50 => scl_c <= '1'; sda_drv <= not cfg_word(2);
        when 51 => scl_c <= '0'; sda_drv <= not cfg_word(1);
        when 52 => scl_c <= '1'; sda_drv <= not cfg_word(1);
        when 53 => scl_c <= '0'; sda_drv <= not cfg_word(0);
        when 54 => scl_c <= '1'; sda_drv <= not cfg_word(0);

        -- ---- ACK 3 ------------------------------------------
        when 55 => scl_c <= '0'; sda_drv <= '0';
        when 56 => scl_c <= '1'; sda_drv <= '0';

        when 57 => scl_c <= '0'; sda_drv <= '0';
        when 58 => scl_c <= '0'; sda_drv <= '1';
        when 59 => scl_c <= '1'; sda_drv <= '1';
        when 60 => scl_c <= '1'; sda_drv <= '0';

        when others => scl_c <= '1'; sda_drv <= '0';
      end case;
    end if;
  end process;

end architecture rtl;
