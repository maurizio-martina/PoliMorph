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
-- Title      : I2C touch configuration
-- Project    : PoliMorph: a continuous touch synthesizer
-------------------------------------------------------------------------------
-- File       : i2c_touch_config.vhd
-- Author     : Maurizio MARTINA
-- Company    : Politecnico di Torino
-- Created    : 2025-05-14
-- Last update: 2026-10-19
-- Platform   : DE1-SoC + MTL2 boards
-- Standard   : VHDL'93/02
-------------------------------------------------------------------------------
-- Description: This file contains an implementation of an I2C touch controller
-- for the touch part of the MTL2 board. Same ports and behaviour as the
-- reference module provided with the board, but written from scratch from the
-- I2C specification and the FT5x06 register map: it contains no third-party
-- code.
-------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity i2c_touch_config is
  port (
    iCLK             : in    std_logic;
    iRSTN            : in    std_logic;
    oREADY           : out   std_logic;
    INT_n            : in    std_logic;
    oREG_X1          : out   unsigned(9 downto 0);
    oREG_Y1          : out   unsigned(8 downto 0);
    oREG_X2          : out   unsigned(9 downto 0);
    oREG_Y2          : out   unsigned(8 downto 0);
    oREG_X3          : out   unsigned(9 downto 0);
    oREG_Y3          : out   unsigned(8 downto 0);
    oREG_X4          : out   unsigned(9 downto 0);
    oREG_Y4          : out   unsigned(8 downto 0);
    oREG_X5          : out   unsigned(9 downto 0);
    oREG_Y5          : out   unsigned(8 downto 0);
    oREG_GESTURE     : out   unsigned(7 downto 0);
    oREG_TOUCH_COUNT : out   unsigned(3 downto 0);
    I2C_SDAT         : inout std_logic;
    I2C_SCLK         : inout std_logic
  );
end entity i2c_touch_config;

architecture rtl of i2c_touch_config is

  -- ---------------------------------------------------------------------------
  -- Constants
  -- ---------------------------------------------------------------------------
  constant cPHASE   : integer := 31;
  constant cGAP_L   : integer := 64;
  constant cGAP_S   : integer := 32;
  constant cDEBOUNCE: integer := 64;
  constant cHOLD    : integer := 64;
  constant cNBYTES  : integer := 31;

  constant cDEV_WR  : std_logic_vector(7 downto 0) := x"70";
  constant cDEV_RD  : std_logic_vector(7 downto 0) := x"71";
  constant cREG0    : std_logic_vector(7 downto 0) := x"00";

  constant cG10 : unsigned(7 downto 0) := to_unsigned(16#10#, 8);
  constant cG14 : unsigned(7 downto 0) := to_unsigned(16#14#, 8);
  constant cG18 : unsigned(7 downto 0) := to_unsigned(16#18#, 8);
  constant cG1C : unsigned(7 downto 0) := to_unsigned(16#1C#, 8);

  constant cKX : unsigned(4 downto 0)  := to_unsigned(25, 5);
  constant cKY : unsigned(15 downto 0) := to_unsigned(52429, 16);

  -- ---------------------------------------------------------------------------
  -- Input synchronisers
  -- ---------------------------------------------------------------------------
  signal int_s  : std_logic_vector(2 downto 0);
  signal scl_s  : std_logic_vector(1 downto 0);
  signal sda_s  : std_logic_vector(1 downto 0);
  signal int_fall : std_logic;

  -- ---------------------------------------------------------------------------
  -- Line drivers
  -- ---------------------------------------------------------------------------
  signal scl_low : std_logic;
  signal sda_low : std_logic;
  signal scl_nx  : std_logic;
  signal sda_nx  : std_logic;

  -- ---------------------------------------------------------------------------
  -- Bit engine
  -- ---------------------------------------------------------------------------
  type t_cmd is (C_START_WR, C_WR, C_RD, C_STOP);
  type t_eng is (E_IDLE, E_START, E_DATA, E_ACK, E_STOP);

  signal e_st    : t_eng;
  signal e_ph    : integer range 0 to 4;
  signal e_bit   : integer range 0 to 7;
  signal e_sr    : std_logic_vector(7 downto 0);
  signal e_rd    : std_logic;
  signal e_ackv  : std_logic;
  signal e_done  : std_logic;
  signal e_dout  : std_logic_vector(7 downto 0);
  signal pre_cnt : integer range 0 to cPHASE;
  signal ph_en   : std_logic;

  signal go      : std_logic;
  signal go_cmd  : t_cmd;
  signal go_din  : std_logic_vector(7 downto 0);
  signal go_ack  : std_logic;

  -- ---------------------------------------------------------------------------
  -- Transaction sequencer FSM
  -- ---------------------------------------------------------------------------
  type t_seq is (Q_IDLE, Q_DEV_WR, Q_GAP1, Q_REG, Q_GAP2, Q_DEV_RD,
                 Q_GAP3, Q_READ, Q_STOP, Q_HOLD);
  signal q_st    : t_seq;
  signal q_wait  : std_logic;
  signal q_arm   : std_logic;
  signal q_cnt   : integer range 0 to 127;
  signal q_nrd   : integer range 0 to cNBYTES;
  signal s_rdy   : std_logic;

  type t_buf is array (0 to cNBYTES-1) of std_logic_vector(7 downto 0);
  signal rbuf : t_buf;

begin

  -----------------------------------------------------------------------------
  -- I2C signals drivers
  -----------------------------------------------------------------------------
  I2C_SCLK <= '0' when scl_low = '1' else 'Z';
  I2C_SDAT <= '0' when sda_low = '1' else 'Z';

  -----------------------------------------------------------------------------
  -- Synchronisers
  -----------------------------------------------------------------------------
  process (iCLK, iRSTN) is
  begin
    if iRSTN = '0' then
      int_s <= (others => '0');
      scl_s <= (others => '1');
      sda_s <= (others => '1');
    elsif rising_edge(iCLK) then
      int_s <= int_s(1 downto 0) & INT_n;
      scl_s <= scl_s(0) & to_x01(I2C_SCLK);
      sda_s <= sda_s(0) & to_x01(I2C_SDAT);
    end if;
  end process;

  int_fall <= int_s(2) and not int_s(1);

  -----------------------------------------------------------------------------
  -- Phase timer: one pulse every cPHASE clocks while the engine is busy.
  -- Frozen while SCL is released but still read low (slave stretching,
  -- or simply the line still rising).
  -----------------------------------------------------------------------------
  process (iCLK, iRSTN) is
  begin
    if iRSTN = '0' then
      pre_cnt <= 0;
      ph_en   <= '0';
    elsif rising_edge(iCLK) then
      ph_en <= '0';
      if e_st = E_IDLE then
        pre_cnt <= 0;
      elsif scl_low = '0' and scl_s(1) = '0' then
        null;                                    -- stretching: hold
      elsif pre_cnt = cPHASE then
        pre_cnt <= 0;
        ph_en   <= '1';
      else
        pre_cnt <= pre_cnt + 1;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Line levels for each engine state / phase (combinational).
  --
  --   START  ph0  SCL keep   SDA high
  --          ph1  SCL high   SDA high
  --          ph2  SCL high   SDA low      <- START
  --          ph3  SCL high   SDA low
  --          ph4  SCL low    SDA low
  --   bit    ph0  SCL low    SDA data     <- data changes only here
  --          ph1  SCL high   SDA data
  --          ph2  SCL high   SDA data     (read: sampled at end of ph2)
  --          ph3  SCL low    SDA data
  --   STOP   ph0  SCL low    SDA low
  --          ph1  SCL high   SDA low
  --          ph2  SCL high   SDA low
  --          ph3  SCL high   SDA high     <- STOP
  -----------------------------------------------------------------------------
  process (e_st, e_ph, e_sr, e_rd, e_ackv, scl_low, sda_low) is
    variable drive_sda : std_logic;
  begin
    scl_nx <= scl_low;
    sda_nx <= sda_low;

    case e_st is
      when E_START =>
        case e_ph is
          when 0      => scl_nx <= scl_low; sda_nx <= '0';
          when 1      => scl_nx <= '0';     sda_nx <= '0';
          when 2 | 3  => scl_nx <= '0';     sda_nx <= '1';
          when others => scl_nx <= '1';     sda_nx <= '1';
        end case;

      when E_DATA | E_ACK =>
        if e_st = E_DATA then
          if e_rd = '1' then
            drive_sda := '0';
          else
            drive_sda := not e_sr(7);
          end if;
        else
          if e_rd = '1' then
            drive_sda := not e_ackv;
          else
            drive_sda := '0';
          end if;
        end if;
        sda_nx <= drive_sda;
        if e_ph = 1 or e_ph = 2 then
          scl_nx <= '0';
        else
          scl_nx <= '1';
        end if;

      when E_STOP =>
        case e_ph is
          when 0      => scl_nx <= '1'; sda_nx <= '1';
          when 1 | 2  => scl_nx <= '0'; sda_nx <= '1';
          when others => scl_nx <= '0'; sda_nx <= '0';
        end case;

      when others =>
        null;
    end case;
  end process;

  -- Registered line drivers (no glitches on the pads)
  process (iCLK, iRSTN) is
  begin
    if iRSTN = '0' then
      scl_low <= '0';
      sda_low <= '0';
    elsif rising_edge(iCLK) then
      scl_low <= scl_nx;
      sda_low <= sda_nx;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Bit engine
  -----------------------------------------------------------------------------
  process (iCLK, iRSTN) is
  begin
    if iRSTN = '0' then
      e_st   <= E_IDLE;
      e_ph   <= 0;
      e_bit  <= 7;
      e_sr   <= (others => '0');
      e_rd   <= '0';
      e_ackv <= '1';
      e_done <= '0';
      e_dout <= (others => '0');
    elsif rising_edge(iCLK) then
      e_done <= '0';

      if e_st = E_IDLE then
        if go = '1' then
          e_ph   <= 0;
          e_bit  <= 7;
          e_sr   <= go_din;
          e_ackv <= go_ack;
          case go_cmd is
            when C_START_WR => e_st <= E_START; e_rd <= '0';
            when C_WR       => e_st <= E_DATA;  e_rd <= '0';
            when C_RD       => e_st <= E_DATA;  e_rd <= '1';
            when C_STOP     => e_st <= E_STOP;  e_rd <= '0';
          end case;
        end if;

      elsif ph_en = '1' then
        case e_st is

          when E_START =>
            if e_ph = 4 then
              e_ph <= 0;
              e_st <= E_DATA;
            else
              e_ph <= e_ph + 1;
            end if;

          when E_DATA =>

            if e_rd = '1' and e_ph = 2 then
              e_sr <= e_sr(6 downto 0) & sda_s(1);
            end if;
            if e_ph = 3 then
              e_ph <= 0;
              if e_rd = '0' then
                e_sr <= e_sr(6 downto 0) & '0';
              end if;
              if e_bit = 0 then
                e_st <= E_ACK;
              else
                e_bit <= e_bit - 1;
              end if;
            else
              e_ph <= e_ph + 1;
            end if;

          when E_ACK =>
            if e_ph = 3 then
              e_ph   <= 0;
              e_dout <= e_sr;
              e_done <= '1';
              e_st   <= E_IDLE;
            else
              e_ph <= e_ph + 1;
            end if;

          when E_STOP =>
            if e_ph = 3 then
              e_ph   <= 0;
              e_done <= '1';
              e_st   <= E_IDLE;
            else
              e_ph <= e_ph + 1;
            end if;

          when others =>
            e_st <= E_IDLE;
        end case;
      end if;
    end if;
  end process;

  -----------------------------------------------------------------------------
  -- Transaction sequencer
  -----------------------------------------------------------------------------
  process (iCLK, iRSTN) is

    -- Issue a command once, then wait for completion
    procedure issue (constant c   : in t_cmd;
                     constant d   : in std_logic_vector(7 downto 0);
                     constant a   : in std_logic;
                     constant nxt : in t_seq) is
    begin
      if q_wait = '0' then
        go     <= '1';
        go_cmd <= c;
        go_din <= d;
        go_ack <= a;
        q_wait <= '1';
      elsif e_done = '1' then
        q_wait <= '0';
        q_cnt  <= 0;
        q_st   <= nxt;
      end if;
    end procedure;

  begin
    if iRSTN = '0' then
      q_st   <= Q_IDLE;
      q_wait <= '0';
      q_arm  <= '0';
      q_cnt  <= 0;
      q_nrd  <= 0;
      s_rdy  <= '0';
      go     <= '0';
      go_cmd <= C_STOP;
      go_din <= (others => '0');
      go_ack <= '1';
      for i in 0 to cNBYTES-1 loop
        rbuf(i) <= (others => '0');
      end loop;

    elsif rising_edge(iCLK) then
      go <= '0';

      case q_st is

        when Q_IDLE =>
          if int_fall = '1' then
            q_arm <= '1';
            q_cnt <= 0;
            q_nrd <= 0;
            s_rdy <= '0';
          elsif q_arm = '1' then
            if q_cnt = cDEBOUNCE then
              q_arm <= '0';
              q_cnt <= 0;
              q_st  <= Q_DEV_WR;
            else
              q_cnt <= q_cnt + 1;
            end if;
          end if;

        when Q_DEV_WR => issue(C_START_WR, cDEV_WR, '1', Q_GAP1);

        when Q_GAP1 =>
          if q_cnt = cGAP_L then q_cnt <= 0; q_st <= Q_REG;
          else q_cnt <= q_cnt + 1; end if;

        when Q_REG    => issue(C_WR, cREG0, '1', Q_GAP2);

        when Q_GAP2 =>
          if q_cnt = cGAP_L then q_cnt <= 0; q_st <= Q_DEV_RD;
          else q_cnt <= q_cnt + 1; end if;

        when Q_DEV_RD => issue(C_START_WR, cDEV_RD, '1', Q_GAP3);

        when Q_GAP3 =>
          if q_cnt = cGAP_S then
            q_cnt <= 0;
            if q_nrd = cNBYTES then
              q_nrd <= 0;
              q_st  <= Q_STOP;
            else
              q_st  <= Q_READ;
            end if;
          else
            q_cnt <= q_cnt + 1;
          end if;

        when Q_READ =>

          if q_wait = '1' and e_done = '1' then
            rbuf(q_nrd) <= e_dout;
            q_nrd       <= q_nrd + 1;
          end if;
          if q_nrd = cNBYTES-1 then
            issue(C_RD, x"00", '1', Q_GAP3);
          else
            issue(C_RD, x"00", '0', Q_GAP3);
          end if;

        when Q_STOP =>
          if q_wait = '1' and e_done = '1' then
            s_rdy <= '1';
          end if;
          issue(C_STOP, x"00", '1', Q_HOLD);

        when Q_HOLD =>
          if q_cnt = cHOLD then
            q_cnt <= 0;
            s_rdy <= '0';
            q_st  <= Q_IDLE;
          else
            q_cnt <= q_cnt + 1;
          end if;

      end case;
    end if;
  end process;

  oREADY   <= s_rdy;

  -----------------------------------------------------------------------------
  -- Output registers: refreshed every clock while oREADY = '1'
  --
  -- FT5x06 register map (index = register address):
  --   1 gesture, 2 touch count [3:0]
  --   touch k (k=0..4): XH = 3+6k, XL = 4+6k, YH = 5+6k, YL = 6+6k
  -----------------------------------------------------------------------------
  process (iCLK, iRSTN) is

    function conv_x (hi, lo : std_logic_vector(7 downto 0)) return unsigned is
      variable raw : unsigned(11 downto 0);
      variable p   : unsigned(16 downto 0);
    begin
      raw := unsigned(hi(3 downto 0)) & unsigned(lo);
      p   := raw * cKX;
      return p(14 downto 5);                         -- (raw*25) >> 5
    end function;

    function conv_y (hi, lo : std_logic_vector(7 downto 0)) return unsigned is
      variable raw : unsigned(11 downto 0);
      variable p   : unsigned(27 downto 0);
    begin
      raw := unsigned(hi(3 downto 0)) & unsigned(lo);
      p   := raw * cKY;
      return p(24 downto 16);                        -- (4*raw)/5, exact
    end function;

    variable g : unsigned(7 downto 0);

  begin
    if iRSTN = '0' then
      oREG_GESTURE     <= (others => '0');
      oREG_TOUCH_COUNT <= (others => '0');
      oREG_X1 <= (others => '0');  oREG_Y1 <= (others => '0');
      oREG_X2 <= (others => '0');  oREG_Y2 <= (others => '0');
      oREG_X3 <= (others => '0');  oREG_Y3 <= (others => '0');
      oREG_X4 <= (others => '0');  oREG_Y4 <= (others => '0');
      oREG_X5 <= (others => '0');  oREG_Y5 <= (others => '0');

    elsif rising_edge(iCLK) then
      if s_rdy = '1' then
        oREG_TOUCH_COUNT <= unsigned(rbuf(2)(3 downto 0));

        g := unsigned(rbuf(1));
        if    g = cG10 then oREG_GESTURE <= cG14;
        elsif g = cG1C then oREG_GESTURE <= cG10;
        elsif g = cG18 then oREG_GESTURE <= cG1C;
        elsif g = cG14 then oREG_GESTURE <= cG18;
        else                oREG_GESTURE <= g;
        end if;

        oREG_X1 <= conv_x(rbuf(3),  rbuf(4));   oREG_Y1 <= conv_y(rbuf(5),  rbuf(6));
        oREG_X2 <= conv_x(rbuf(9),  rbuf(10));  oREG_Y2 <= conv_y(rbuf(11), rbuf(12));
        oREG_X3 <= conv_x(rbuf(15), rbuf(16));  oREG_Y3 <= conv_y(rbuf(17), rbuf(18));
        oREG_X4 <= conv_x(rbuf(21), rbuf(22));  oREG_Y4 <= conv_y(rbuf(23), rbuf(24));
        oREG_X5 <= conv_x(rbuf(27), rbuf(28));  oREG_Y5 <= conv_y(rbuf(29), rbuf(30));
      end if;
    end if;
  end process;

end architecture rtl;
