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
  assign uio_out[7:1] = '0;
  assign uio_oe  = 8'b0000_0001;

  // List all unused inputs to prevent warnings
  wire _unused = &{ena, clk, rst_n, 1'b0};

  RangeFinder rf (.data_in(ui_in), .clock(clk), .reset(rst_n),
                  .go(uio_in[0]), .finish(uio_in[1]), .range(uo_out),
                  .error(uio_out[0]));

endmodule


module RangeFinder
   #(parameter WIDTH=8)
    (input  logic [WIDTH-1:0] data_in,
     input  logic             clock, reset,
     input  logic             go, finish,
     output logic [WIDTH-1:0] range,
     output logic             error);


enum logic [1:0] {IDLE, CHECK, ERROR} state, next_state;

logic ld_reg; // in the state where data_in is valid and may be loaded
logic go_prev, go_pos; // for posedge checking
logic [WIDTH-1:0] min, max;

assign go_pos = go & ~go_prev;

// update min/max
always_ff @(posedge clock, posedge reset) begin
   if(reset) begin
      max <= '0;
      min <= '1;
   end
   else begin
      // set starting comparison values
      if(go_pos & ld_reg) begin
         min <= data_in;
         max <= data_in;
      end
      else if(ld_reg & (data_in < min)) begin
         min <= data_in;
      end
      else if(ld_reg & (data_in > max)) begin
         max <= data_in;
      end
      else begin
         min <= min;
         max <= max;
      end
   end
end

// set the range output
always_comb begin
   if(finish) begin
      // check if final data_in value is a min or max
      if(data_in > max) begin
         range = data_in - min;
      end
      else if(data_in < min) begin
         range = max - data_in;
      end
      else begin
         range = max - min;
      end
   end
   else begin
      range = '0;
   end
end

always_comb begin
   ld_reg = 1'b0;
   error = 1'b0;
   unique case(state)
      IDLE: begin
         // error
         if(finish) begin
            next_state = ERROR;
         end
         // start checking data_in
         else if(go_pos) begin
            next_state = CHECK;
            ld_reg = 1'b1;
         end
         // stay here
         else begin
            next_state = IDLE;
         end
      end
      CHECK: begin
         // error
         if(go_pos) begin
            next_state = ERROR;
         end
         // stop checking data_in
         else if(finish) begin
            next_state = IDLE;
         end
         // keep checking data_in
         else begin
            next_state = CHECK;
            ld_reg = 1'b1;
         end
      end
      ERROR: begin
         error = 1'b1;
         // restart sequence check
         if(go_pos) begin
            next_state = CHECK;
            ld_reg = 1'b1;
         end
         // stay in error until next go
         else begin
            next_state = ERROR;
         end
      end
   endcase
end

// state update
always_ff @(posedge clock, posedge reset) begin
   if(reset) begin 
      state <= IDLE;
      go_prev <= 1'b0;
   end
   else begin
      state <= next_state;
      go_prev <= go;
   end
end

endmodule: RangeFinder