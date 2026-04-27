/*
 * Copyright (c) 2024 Your Name
 * SPDX-License-Identifier: Apache-2.0
 */

`default_nettype none

module tt_um_example_sillylad (
    input  wire [7:0] ui_in,    // Dedicated inputs
    output wire [7:0] uo_out,   // Dedicated outputs
    input  wire [7:0] uio_in,   // IOs: Input path
    output wire [7:0] uio_out,  // IOs: Output path
    output wire [7:0] uio_oe,   // IOs: Enable path (active high: 0=input, 1=output)
    input  wire       ena,      // always 1 when the design is powered, so you can ignore it
    input  wire       clk,      // clock
    input  wire       rst_n     // reset_n - low to reset
);

  // All output pins must be assigned. If not used, assign to 0.
  // assign uio_out[7:1] = '0;
  assign uio_oe  = '1;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};

ChipInterface ci (.clk(clk), .btn({ui_in[7:1], rst_n}),
                  .R0(uo_out[7]), .R1(uo_out[6]),
                  .G0(uo_out[5]), .G1(uo_out[4]),
                  .B0(uo_out[3]), .B1(uo_out[2]),
                  .VGA_HS(uo_out[1]), .VGA_VS(uo_out[0]), .led(uio_out));

endmodule