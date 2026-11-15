# PoliMorph

PoliMorph is a continuous-touch polyphonic synthesizer for the Terasic
DE1-SoC board with the MTL2 multi-touch display module. Up to five fingers
play independent voices: the X coordinate selects the pitch (continuously or
locked to the notes of the selected scale), the Y coordinate morphs the
timbre from a sine wave to a band-limited sawtooth.

NOTE: This implementation is far from optimized, as it is intended as a proof of concept.

[![Short project explanation](https://img.youtube.com/vi/N6T8fDekDA4/hqdefault.jpg)](https://www.youtube.com/watch?v=N6T8fDekDA4)

[![Short project demo](https://img.youtube.com/vi/BP-eFHD12Ig/hqdefault.jpg)](https://www.youtube.com/watch?v=BP-eFHD12Ig)

## Hardware

- Terasic DE1-SoC (Cyclone V 5CSEMA5F31C6)
- Terasic MTL2 (800x480 display, FT5x06 touch controller)
- On-board WM8731 audio codec (line out / headphones)

## Repository layout

```
rtl/        VHDL sources (top level: polimorph.vhd)
```

The Quartus project files (`.qpf`, `.qsf`) and timing constraints (`.sdc`) are required to build the
design.

## Controls

| Control   | Function                                              |
|-----------|-------------------------------------------------------|
| SW[3:0]   | Root note (0 = C ... 11 = B)                          |
| SW[5:4]   | Number of octaves (2, 3 or 4)                         |
| SW[9:6]   | Scale preset                                          |
| KEY[0]    | Starting octave down (C1 minimum)                     |
| KEY[1]    | Starting octave up (C5 maximum)                       |
| KEY[2]    | Toggle pitch lock                                     |
| KEY[3]    | Toggle sharp/flat naming of the root note             |
| KEY[3]+KEY[0] | Reset                                             |

## Clocks

- `CLOCK_50`: audio synthesis and codec interface, touch controller
- 33 MHz (PLL `pll33`): display, touch management, note mapping
- 12.288 MHz (PLL `pll_audio`): WM8731 master clock

## License

Copyright 2026 Maurizio Martina, Politecnico di Torino.
Licensed under the Solderpad Hardware License v2.1
(`SPDX-License-Identifier: Apache-2.0 WITH SHL-2.1`). See `LICENSE`.
