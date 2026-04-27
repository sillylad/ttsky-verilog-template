`default_nettype none

module ChipInterface (
    input logic clk,
    input logic [6:0] btn,
    output logic R0, R1, G0, G1, B0, B1, VGA_HS, VGA_VS,
    output logic [7:0] led
);
    assign led = '0;

    // synchronize all input buttons w/2 FFs
    logic tmp_btn, rst_n;
    logic [3:0] tmp_dir, dir, sync_dir;
    logic tmp_start_game, start_game;

    always_ff @(posedge clk) begin
        tmp_btn <= btn[0];        
        rst_n <= tmp_btn;

        tmp_dir <= btn[6:3];
        sync_dir <= tmp_dir;

        tmp_start_game <= btn[1];
        start_game <= tmp_start_game;
    end 

    // Pulse stretch the dir buttons so button presses aren't missed by the
    // slower game_clk
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            dir <= 1'b0;
        end
        else if(game_clk) begin
            dir <= sync_dir;
        end
        else if(sync_dir) begin
            dir <= sync_dir;
        end
    end

    // VGA signals for driving display
    logic [9:0] col;
    logic [9:0] row;
    logic [3:0] VGA_R, VGA_G, VGA_B;
    logic blank;
    logic game_clk, clk_60HZ;

    // Drive VGA timing signals
    vga vga_640_480 (.clk(clk), .rst_n(rst_n), .HS(VGA_HS), .VS(VGA_VS),
                    .blank(blank), .row(row), .col(col), .game_clk(clk_60HZ));

                
    // divide 60hz game clock by 8 so it's not so ZOOMIN'
    // 133ms/tile, similar to Google snake game for reference
    logic [2:0] frame_cnt;
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            frame_cnt <= '0;
        end
        else if(clk_60HZ) begin
            frame_cnt <= frame_cnt + 1'b1;
        end
        else begin
            frame_cnt <= frame_cnt;
        end
    end

    assign game_clk = clk_60HZ & (frame_cnt == 3'd0);


    // Module handling all the snake game logic and coloring
    Snake snek (.clk(clk), .rst_n(rst_n), .game_clk(game_clk),
                .start_game(start_game), .dir(dir),
                .row(row), .col(col), .VGA_R(VGA_R), .VGA_G(VGA_G), .VGA_B(VGA_B));

    logic [5:0] rgb;
    
    // blank out the RGB pins in non-display periods
    assign rgb = {VGA_R[1:0], VGA_G[1:0], VGA_B[1:0]};
    assign {R1, R0, G1, G0, B1, B0} = (~blank) ? rgb : '0;

endmodule : ChipInterface
