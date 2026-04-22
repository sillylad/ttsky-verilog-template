`default_nettype none

module ChipInterface (
    input logic clk,
    input logic [6:0] btn,
    output logic R0, R1, G0, G1, B0, B1, VGA_HS, VGA_VS,
    output logic [7:0] led
);

    // 40Mhz needed for 800x600
    logic pll_locked, clk_40;

    // pll40M c40 (.clk_25(clk), .clk_40(clk_40), .locked(pll_locked));
    assign clk_40 = clk;
    // synchronize buttons
    logic tmp_btn, rst_n;
    logic [3:0] tmp_dir, dir;
    logic tmp_start_game, start_game;

    always_ff @(posedge clk_40) begin
        tmp_btn <= btn[0];        
        rst_n <= tmp_btn;

        tmp_dir <= btn[6:3];
        dir <= tmp_dir;

        tmp_start_game <= btn[1];
        start_game <= tmp_start_game;
    end 

    // VGA for driving display
    logic [9:0] col;
    logic [9:0] row;
    logic [7:0] VGA_R, VGA_G, VGA_B;
    logic blank;
    logic game_clk, clk_60HZ;
    logic [1:0] curr_dir;
    logic [6:0] snake_length;
    logic [5:0] head_pos;
    logic is_snake;

    // Drive VGA timing signals
    vga vga_800_600 (.clk(clk_40), .rst_n(rst_n), .HS(VGA_HS), .VS(VGA_VS),
                    .blank(blank), .row(row), .col(col), .game_clk(clk_60HZ));

                
    // divide 60hz game clock so it's not so ZOOMIN'
    // every 30 frames -> 2 hz refresh rate
    logic [4:0] frame_cnt;
    always_ff @(posedge clk_40, negedge rst_n) begin
        if(~rst_n) begin
            frame_cnt <= '0;
        end
        else if(clk_60HZ) begin
            frame_cnt <= (frame_cnt == 5'd9) ? '0 : frame_cnt + 1'b1;
        end
        else begin
            frame_cnt <= frame_cnt;
        end
    end

    assign game_clk = clk_60HZ & (frame_cnt == 5'd0);

    logic [3:0] debug_nc;

    // Module handling all the snake game logic and coloring
    Snake snek (.clk(clk_40), .rst_n(rst_n), .game_clk(game_clk),
                .start_game(start_game), .dir(dir),
                .row(row), .col(col), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B),
                .curr_dir(curr_dir), .snake_length(snake_length),
                .head_pos(head_pos), .is_snake(is_snake), .debug_nc(debug_nc));

    // generate test pattern
    logic [5:0] rgb;

    // vga_test_pattern vtp(.row(row), .col(col), .rgb(rgb));
    assign rgb = {VGA_R[1:0], VGA_G[1:0], VGA_B[1:0]};
    assign {R1, R0, G1, G0, B1, B0} = (~blank) ? rgb : '0;
    
    // assign led = {R1, R0, G1, G0, B1, B0};
    // assign led = curr_dir;

    // logic [5:0] frame_count;
    // always_ff @(posedge clk, negedge rst_n) begin
    //     if(~rst_n) frame_count <= '0;
    //     else if(game_clk) frame_count <= frame_count + 1;
    // end
    // assign led = frame_count;

    assign led = {debug_nc, 1'b0, head_pos[2:0]};

endmodule : ChipInterface

// Test vertical and horizontal sync with test pattern
module vga_test_pattern (
    input logic [9:0] row, col,
    output logic [5:0] rgb
);

    always_comb begin
        if((row == 0) & (col == 0)) begin
            rgb = '1;
        end
        else if((row == 10'd0) | (row == 10'd479)) begin
            rgb = 6'b11_00_11;
        end
        else if((col == 0) | (col == 10'd639)) begin
            rgb = 6'b11_00_00;
        end
        else if((col == 10'd50) | (col == 10'd70) | (col == 10'd100)) begin
            rgb = 6'b00_00_11;
        end

        else if(col <= 10'd639 | col >= 10'd0) begin
            rgb = 6'b00_11_00;
        end
        else begin
            rgb = '0;
        end
    end


endmodule : vga_test_pattern



// diamond 3.7 accepts this PLL
// diamond 3.8-3.9 is untested
// diamond 3.10 or higher is likely to abort with error about unable to use feedback signal
// cause of this could be from wrong CPHASE/FPHASE parameters
module pll40M
(
    input clk_25, // 25 MHz, 0 deg
    output clk_40, // 40 MHz, 0 deg
    output locked
);
(* FREQUENCY_PIN_CLKI="25" *)
(* FREQUENCY_PIN_CLKOP="40" *)
(* ICP_CURRENT="12" *) (* LPF_RESISTOR="8" *) (* MFG_ENABLE_FILTEROPAMP="1" *) (* MFG_GMCREF_SEL="2" *)
EHXPLLL #(
        .PLLRST_ENA("DISABLED"),
        .INTFB_WAKE("DISABLED"),
        .STDBY_ENABLE("DISABLED"),
        .DPHASE_SOURCE("DISABLED"),
        .OUTDIVIDER_MUXA("DIVA"),
        .OUTDIVIDER_MUXB("DIVB"),
        .OUTDIVIDER_MUXC("DIVC"),
        .OUTDIVIDER_MUXD("DIVD"),
        .CLKI_DIV(5),
        .CLKOP_ENABLE("ENABLED"),
        .CLKOP_DIV(15),
        .CLKOP_CPHASE(7),
        .CLKOP_FPHASE(0),
        .FEEDBK_PATH("CLKOP"),
        .CLKFB_DIV(8)
    ) pll_i (
        .RST(1'b0),
        .STDBY(1'b0),
        .CLKI(clk_25),
        .CLKOP(clk_40),
        .CLKFB(clk_40),
        .CLKINTFB(),
        .PHASESEL0(1'b0),
        .PHASESEL1(1'b0),
        .PHASEDIR(1'b1),
        .PHASESTEP(1'b1),
        .PHASELOADREG(1'b1),
        .PLLWAKESYNC(1'b0),
        .ENCLKOP(1'b0),
        .LOCK(locked)
	);
endmodule
