`default_nettype none

// Parameterizable VGA module
module vga
   (input logic clk, rst_n,
    output logic HS, VS, blank,
    output logic [9:0] row,
    output logic [9:0] col,
    output logic game_clk);

    // timing parameters to use for 600x800 resolution
    // localparam NUM_ROWS = 600;
    // localparam NUM_COLS = 800;
    // localparam HS_SYNC  = 1056;
    // localparam HS_DISP  = 800;
    // localparam HS_PW    = 128;
    // localparam HS_FP    = 40;
    // localparam HS_BP    = 88;

    // localparam VS_SYNC = 628;
    // localparam VS_DISP = 600;
    // localparam VS_PW   = 4;
    // localparam VS_FP   = 1;
    // localparam VS_BP   = 23;

    // localparam PW_POS_POLARITY = 1; // negative (0) for 640x480, pos for 800x600

    // parameters for 640x480 resolution
    localparam NUM_ROWS = 480;
    localparam NUM_COLS = 640;
    localparam HS_SYNC  = 800;
    localparam HS_DISP  = 640;
    localparam HS_PW    = 96;
    localparam HS_FP    = 16;
    localparam HS_BP    = 48;

    localparam VS_SYNC = 525;
    localparam VS_DISP = 480;
    localparam VS_PW   = 2;
    localparam VS_FP   = 10;
    localparam VS_BP   = 33;

    localparam PW_POS_POLARITY = 0; // negative (0) for 640x480, pos for 800x600

    logic [19:0] VS_count;
    logic [10:0] HS_count;

    logic is_hs_pw, is_hs_bp, is_hs_disp, is_hs_fp;
    logic is_vs_pw, is_vs_bp, is_vs_disp, is_vs_fp;

    // HS, VS counters
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            {VS_count, HS_count} <= '0;
        end
        else begin
            HS_count <= ((HS_count == (HS_SYNC - 1'b1)) ? '0 : HS_count + 1'b1);
            if(HS_count == HS_SYNC - 1'b1) begin
                VS_count <= ((VS_count == (VS_SYNC - 1'b1)) ? '0 : VS_count + 1'b1);
            end
        end
    end

    assign row = is_vs_disp ? (VS_count - (VS_PW + VS_BP)) : '0;
    assign col = is_hs_disp ? (HS_count - (HS_PW + HS_BP)) : '0;

    assign is_hs_pw = (HS_count < HS_PW);
    assign is_hs_bp = (HS_PW <= HS_count) && (HS_count < (HS_PW + HS_BP));
    assign is_hs_disp = ((HS_PW + HS_BP) <= HS_count) && (HS_count < (HS_PW + HS_BP + HS_DISP));
    assign is_hs_fp = ((HS_PW + HS_BP + HS_DISP) <= HS_count) && (HS_count < (HS_PW + HS_BP + HS_DISP + HS_FP));

    assign is_vs_pw = (VS_count < VS_PW);
    assign is_vs_bp = (VS_PW <= VS_count) && (VS_count < (VS_PW + VS_BP));
    assign is_vs_disp = ((VS_PW + VS_BP) <= VS_count) && (VS_count < (VS_PW + VS_BP + VS_DISP));
    assign is_vs_fp = ((VS_PW + VS_BP + VS_DISP) <= VS_count) && (VS_count < (VS_PW + VS_BP + VS_DISP + VS_FP));
    
    //FINAL OUTPUTS OF VGA MODULE
    assign HS = (PW_POS_POLARITY) ? is_hs_pw : ~is_hs_pw;
    assign VS = (PW_POS_POLARITY) ? is_vs_pw : ~is_vs_pw;
    assign blank = ~(is_hs_disp & is_vs_disp);

    // Generate game clock for use in the game modules, to go off the clock after
    // the entire frame is displayed (basically negedge on is_vs_disp)
    logic prev_is_vs_disp;
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            // not in display period before the very start, so reset to 0
            prev_is_vs_disp <= 1'b0;
        end
        else begin
            prev_is_vs_disp <= is_vs_disp;
        end
    end

    assign game_clk = prev_is_vs_disp & ~is_vs_disp;

endmodule : vga