`default_nettype none

typedef enum logic [1:0] {MOVE_UP, MOVE_LEFT, MOVE_RIGHT, MOVE_DOWN} snake_move;

localparam MAX_SNAKE_SIZE = 20;
localparam MAX_GAME_SCORE = 8'h99;

module Snake (
    input logic clk, rst_n,
    input logic game_clk,
    input logic start_game,
    input logic [3:0] dir,
    input logic [9:0] row, col,
    output logic [3:0] VGA_R, VGA_G, VGA_B
);
    logic is_snake;
    logic [5:0] head_pos;
    logic [$clog2(MAX_SNAKE_SIZE) : 0] snake_length;

    // MAX_SNAKE_SIZE-element shift register for snake motion tracking
    logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data;
    logic [MAX_SNAKE_SIZE - 1:0] snake_valid;
    logic snake_init, grow, snake_enable, collision;
    logic [5:0] new_head;

    enum logic [1:0] {IDLE, MOVING, DEAD} curr_state;
    
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            curr_state <= IDLE;
            snake_init <= 1'b0;
            snake_enable <= 1'b0;
        end
        else begin
            case(curr_state)
                IDLE: begin
                    curr_state <= (start_game & game_clk) ? MOVING : IDLE;
                    snake_init <= 1'b0;
                    snake_enable <= 1'b0;
                end
                MOVING: begin
                    curr_state <= (collision) ? DEAD : MOVING;
                    snake_init <= collision;
                    snake_enable <= ~collision;
                end
                DEAD: begin
                    curr_state <= (snake_init & game_clk) ? IDLE : DEAD;
                    snake_init <= (snake_init & game_clk) ? 1'b0 : 1'b1;
                    snake_enable <= 1'b0;
                end
                default: begin
                    curr_state <= IDLE;
                    snake_init <= 1'b0;
                    snake_enable <= 1'b0;
                end
            endcase
        end
    end

    assign grow = (new_head == fruit_pos);

    // Stores the current snake data and updates the snake position as needed
    // Output snake_data array for use by other blocks
    Snake_Register sreg (.clk(clk), .rst_n(rst_n), .game_clk(game_clk),
                    .snake_enable(snake_enable),
                    .snake_init(snake_init),
                    .dir(dir),
                    .grow(grow),
                    .snake_data(snake_data),
                    .snake_length(snake_length),
                    .snake_valid(snake_valid),
                    .new_head(new_head),
                    .collision(collision));

    assign head_pos = snake_data[0]; // pull out of snake_register for debug
    
    // Fruit
    logic [5:0] fruit_pos;
    PRNG fruit_gen (.clk(clk), .game_clk(game_clk), .rst_n(rst_n),
                    .snake_data(snake_data), .snake_valid(snake_valid),
                    .grow(grow), .snake_init(snake_init), .fruit_pos(fruit_pos));

    // Scoring
    // Snake can continue to play after MAX_SNAKE_SIZE is reached, so score widths
    // are wider than MAX_SNAKE_SIZE -> cap at 99 so it fits in 2 BCD digits lol
    // these scores are BCD values {4 bits upper bcd digit, 4 bits lower bcd digit}
    logic [7:0] high_score, curr_score;
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            curr_score <= '0;
            high_score <= '0;
        end
        else begin
            // died
            if(collision) begin
                // update high score
                if(curr_score > high_score) begin
                    high_score <= curr_score; 
                end
                // reset current score cuz ded
                curr_score <= '0;
            end
            else if(grow & game_clk) begin
                if(curr_score == {4'd9, 4'd9}) begin
                    curr_score <= curr_score;
                end
                else begin
                    curr_score[3:0] <= (curr_score[3:0] == 4'd9) ? 4'd0 : (curr_score[3:0] + 1'b1);
                    curr_score[7:4] <= (curr_score[3:0] == 4'd9) ? (curr_score[7:4] + 1'b1) : curr_score[7:4];
                end
            end
        end
    end

    // Color
    Color_Gameboard cgb(.snake_data(snake_data),
                        .snake_length(snake_length),
                        .snake_valid(snake_valid),
                        .curr_score(curr_score),
                        .high_score(high_score),
                        .fruit_pos(fruit_pos),
                        .row(row), .col(col), .is_snake(is_snake), .*);

endmodule : Snake


// Update the snake shift register (location of the snake) and 8x8 grid of 
// snake tiles
module Snake_Register (
    input logic clk, rst_n, game_clk,
    input logic [3:0] dir,
    input logic grow, snake_enable, snake_init,
    input logic [MAX_SNAKE_SIZE - 1:0] snake_valid,
    output logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data, // shift register values
    output logic [$clog2(MAX_SNAKE_SIZE) : 0] snake_length,
    output logic [5:0] new_head,
    output logic collision
);

    snake_move decoded_dir, fast_dir, curr_dir;
    logic wall_collision, self_collision;

    // Have a button priority for simplicity, in case multiple are pressed
    // also reject invalid moves (like moving right when currently moving left, etc.)
    always_comb begin
        if(dir[3] & (curr_dir != MOVE_LEFT)) begin
            decoded_dir = MOVE_RIGHT;
        end
        else if(dir[2] & (curr_dir != MOVE_RIGHT)) begin
            decoded_dir = MOVE_LEFT;
        end
        else if(dir[1] & (curr_dir != MOVE_UP)) begin
            decoded_dir = MOVE_DOWN;
        end
        else if(dir[0] & (curr_dir != MOVE_DOWN)) begin
            decoded_dir = MOVE_UP;
        end
        // keep snake moving in same direction
        else begin
            decoded_dir = curr_dir;
        end
    end

    // reset move direction is just to the right
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            curr_dir <= MOVE_RIGHT;
        end
        else if(game_clk) begin
            curr_dir <= (snake_init) ? MOVE_RIGHT : fast_dir;
        end
    end

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            fast_dir <= MOVE_RIGHT;
        end
        else if(snake_init) begin
            fast_dir <= MOVE_RIGHT;
        end
        else if(snake_enable) begin
            fast_dir <= decoded_dir;
        end
    end

    task initialize_snake();
        // Initial snake length is 3 tiles
        snake_length <= ($clog2(MAX_SNAKE_SIZE) + 1)'('d3);

        // Initial snake shift register = horizontal snake facing left
        for(int m = 0; m < MAX_SNAKE_SIZE; m++) begin
            // set the initial head of the snake
            if(m == 0) begin
                snake_data[m] <= {3'd3, 3'd3};
            end
            else if(m == 1) begin
                snake_data[m] <= {3'd3, 3'd2};
            end
            // set the initial tail of the snake
            else if(m == 2) begin
                snake_data[m] <= {3'd3, 3'd1};
            end
            else begin
                snake_data[m] <= '0;
            end
        end
    endtask

    always_comb begin
        unique case(curr_dir)
            MOVE_UP: new_head = {snake_data[0][5:3] - 3'd1, snake_data[0][2:0]};
            MOVE_RIGHT: new_head = {snake_data[0][5:3], snake_data[0][2:0] + 3'd1};
            MOVE_LEFT: new_head = {snake_data[0][5:3], snake_data[0][2:0] - 3'd1};
            MOVE_DOWN: new_head = {snake_data[0][5:3] + 3'd1, snake_data[0][2:0]};
        endcase
    end

    logic [3:0] wall_collision_all;

    // hit the top
    assign wall_collision_all[0] = (curr_dir == MOVE_UP) & (new_head[5:3] == 3'd7);
    // hit the bottom
    assign wall_collision_all[1] = (curr_dir == MOVE_DOWN) & (new_head[5:3] == 3'd0);
    // hit the left side
    assign wall_collision_all[2] = (curr_dir == MOVE_LEFT) & (new_head[2:0] == 3'd7);
    // hit the right side
    assign wall_collision_all[3] = (curr_dir == MOVE_RIGHT) & (new_head[2:0] == 3'd0);

    assign wall_collision = (|wall_collision_all) & snake_enable;


    // Sequential self-collision scan cuz we out of space
    logic [$clog2(MAX_SNAKE_SIZE) - 1 : 0] check_idx;
    logic self_collision_found;

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            check_idx <= '0;
            self_collision_found <= 1'b0;
        end
        // reset check positions and stuff since a new game period has started
        else if(game_clk) begin
            check_idx <= '0;
            self_collision_found <= 1'b0;
        end
        // spin on the FAST clock to do the check
        else begin
            // not at end of snake yet, keep incrementing
            if(check_idx != ($clog2(MAX_SNAKE_SIZE)'(MAX_SNAKE_SIZE - 1))) begin
                check_idx <= check_idx + 1'b1;
            end
            if(snake_data[check_idx][5:3] == new_head[5:3] &
               snake_data[check_idx][2:0] == new_head[2:0] &
               snake_valid[check_idx]) begin
                self_collision_found <= 1'b1;
            end
        end
    end

    assign self_collision = self_collision_found & snake_enable;

    assign collision = wall_collision | self_collision;

    // Update snake register
    always_ff @(posedge clk, negedge rst_n) begin
        // reset snake in the middle of the board
        if(~rst_n) begin
            initialize_snake();
        end
        // else begin
        else if(game_clk) begin
            // restart the snake on the game clock only
            if(snake_init) begin
                initialize_snake();
            end
            // Only move the snake if a game has commenced
            else if(snake_enable) begin
                if(snake_length == MAX_SNAKE_SIZE) begin
                    snake_length <= snake_length;
                end
                else begin
                    snake_length <= grow ? snake_length + 1'b1 : snake_length;
                end
                // Update tiles
                for(int j = MAX_SNAKE_SIZE - 1; j > 0; j--) begin
                    snake_data[j] <= snake_data[j-1];
                end
                snake_data[0] <= new_head;
            end
        end
        else begin
            snake_data <= snake_data;
            snake_length <= snake_length;
        end
    end
    

endmodule : Snake_Register

// 6-bit PRNG
// Generate "random" value between 0 -> 63 to get next fruit pos somewhere on
// the board (8x8 = 64 possible tiles)
module PRNG (
    input logic clk, rst_n,
    input logic game_clk,
    input logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data,
    input logic [MAX_SNAKE_SIZE - 1:0] snake_valid,
    input logic grow, snake_init,
    output logic [5:0] fruit_pos
);

    logic valid_fruit, shift, get_new_pos;


    logic [MAX_SNAKE_SIZE - 1:0] fruit_on_snake;

    // spin lfsr on faster clock so it can resolve in time for next game_clk
    logic [5:0] lfsr_out;
    LFSR_6_BIT lfsr(.clk(clk), .rst_n(rst_n), .shift(shift),
                    .lfsr_out(lfsr_out));

    assign shift = ~valid_fruit & get_new_pos;

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            get_new_pos <= 1'b0;
        end
        // trigger new fruit position search
        else if((grow & game_clk)) begin
            get_new_pos <= 1'b1;
        end
        // stop searching when valid fruit is found
        else if(valid_fruit & get_new_pos) begin
            get_new_pos <= 1'b0;
        end
    end

    // update visible fruit_pos only when a valid tile has been found (max MAX_SNAKE_SIZE - 1 clocks)
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            fruit_pos <= {3'd3, 3'd6};
        end
        // make sure fruit isn't on top of the snake when snake respawns in center
        else if(snake_init & game_clk) begin
            fruit_pos <= {3'd3, 3'd6};
        end
        // update visible fruit on game clock only (high for 1 clock only)
        else if(valid_fruit & get_new_pos) begin
            fruit_pos <= lfsr_out;
        end
    end

    // check if the proposed fruit tile is on top of the snake
    // parallel combinational search since lfsr may take many more attempts to resolve
    genvar i;
    generate
        for(i = 0; i < MAX_SNAKE_SIZE; i++) begin
            assign fruit_on_snake[i] =  (snake_data[i][5:3] == lfsr_out[5:3]) & 
                                        (snake_data[i][2:0] == lfsr_out[2:0]) & 
                                        (snake_valid[i]);
        end
    endgenerate

    // conditions for valid fruit: not where the snake is, and in a different
    // place than the previous fruit (these conditions should overlap)
    assign valid_fruit = ~(|fruit_on_snake) & (lfsr_out != fruit_pos);

endmodule : PRNG

// LFSR to generate sequence of pseudorandom 6-bit numbers
module LFSR_6_BIT(
    input logic clk, rst_n, shift,
    output logic [5:0] lfsr_out
);

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            // reset lfsr to seed, but make sure seed isn't 0 else lfsr will lock
            lfsr_out <= 6'b1;
        end
        else if(shift) begin
            lfsr_out[5] <= lfsr_out[0];
            lfsr_out[4] <= lfsr_out[5] ^ lfsr_out[0];
            lfsr_out[3] <= lfsr_out[4];
            lfsr_out[2] <= lfsr_out[3] ^ lfsr_out[0];
            lfsr_out[1] <= lfsr_out[2] ^ lfsr_out[0];
            lfsr_out[0] <= lfsr_out[1];
        end
        else begin
            lfsr_out <= lfsr_out;
        end
    end

endmodule : LFSR_6_BIT


// Convert 4-bit BCD to seven-segment code
module BCD_to_SS (
    input logic [3:0] value,
    output logic [6:0] ss_value
);

    always_comb begin
        case (value)
            4'h0: ss_value = 7'b1111110;
            4'h1: ss_value = 7'b0110000;
            4'h2: ss_value = 7'b1101101;
            4'h3: ss_value = 7'b1111001;
            4'h4: ss_value = 7'b0110011;
            4'h5: ss_value = 7'b1011011;
            4'h6: ss_value = 7'b1011111;
            4'h7: ss_value = 7'b1110000;
            4'h8: ss_value = 7'b1111111;
            4'h9: ss_value = 7'b1111011;
            default: ss_value = 7'b0000000;
        endcase
    end

endmodule : BCD_to_SS

// check which of the seven segments the VGA row and col are on
module VGA_Segment_Check(
    input logic [3:0] x_pos,
    input logic top_row, middle_row, bottom_row, top_half, bottom_half, in_box,
    output logic [6:0] ss_out
);

    logic left_lane, right_lane, middle_lane;

    assign left_lane = (x_pos == 4'd0);
    assign right_lane = (x_pos == 4'd9);
    assign middle_lane = ~left_lane & ~right_lane & in_box;
    
    logic [6:0] ss_out_init;

    // {a, b, c, d, e, f, g}
    assign ss_out_init[6] = middle_lane & top_row;
    assign ss_out_init[5] = right_lane & top_half;
    assign ss_out_init[4] = right_lane & bottom_half;
    assign ss_out_init[3] = middle_lane & bottom_row;
    assign ss_out_init[2] = left_lane & bottom_half;
    assign ss_out_init[1] = left_lane & top_half;
    assign ss_out_init[0] = middle_lane & middle_row;

    assign ss_out = (in_box) ? ss_out_init : '0;

endmodule : VGA_Segment_Check

// Display the high score (left) and current game score (right) on the VGA
module Score_Color(
    input logic [7:0] curr_score, high_score,
    input logic [9:0] row, col,
    output logic is_score
);
    // which segments we are supposed to display based on the score number
    logic [6:0] curr_ss_lsd, curr_ss_msd, high_ss_lsd, high_ss_msd;
    
    // which segment are we in right now based on vga row/col
    logic [6:0] disp_curr_ss_lsd, disp_curr_ss_msd, disp_high_ss_lsd, disp_high_ss_msd;

    // convert scores to seven-segment encoding
    BCD_to_SS bts_curr_lsd (.value(curr_score[3:0]), .ss_value(curr_ss_lsd));
    BCD_to_SS bts_curr_msd (.value(curr_score[7:4]), .ss_value(curr_ss_msd));
    BCD_to_SS bts_high_lsd (.value(high_score[3:0]), .ss_value(high_ss_lsd));
    BCD_to_SS bts_high_msd (.value(high_score[7:4]), .ss_value(high_ss_msd));

    // shared row-checking signals across the 4 different digits being displayed
    // (2 for curr, 2 for high)
    logic top_row, middle_row, bottom_row, top_half, bottom_half, in_score_box_row;

    // convert to tiles instead of raw pixels to make arithmetic smaller
    logic [4:0] y_pos;
    assign y_pos = row[9:3] - 7'd18;
    assign top_row = (y_pos == 5'd0);
    assign middle_row = (y_pos >= 5'd11) & (y_pos < 5'd13);
    assign bottom_row = (y_pos >= 5'd23) & (y_pos < 5'd24);
    assign top_half = (y_pos < 5'd13);
    assign bottom_half = (y_pos >= 5'd11);
    assign in_score_box_row = (row[9:3] >= 7'd18) & (row[9:3] < 7'd42);

    // check if vga is in the corresponding digit's box region
    logic  in_box_c_l, in_box_c_m, in_box_h_l, in_box_h_m;

    assign in_box_c_l = (col[9:3] >= 7'd69) & (col[9:3] < 7'd79);
    assign in_box_c_m = (col[9:3] >= 7'd57) & (col[9:3] < 7'd67);
    assign in_box_h_l = (col[9:3] >= 7'd13) & (col[9:3] < 7'd23);
    assign in_box_h_m = (col[9:3] >= 7'd1)  & (col[9:3] < 7'd11);

    // x-offset for each digit's box region
    logic [3:0] x_pos_c_l, x_pos_c_m, x_pos_h_l, x_pos_h_m;
    assign x_pos_c_l = col[9:3] - 7'd69;
    assign x_pos_c_m = col[9:3] - 7'd57;
    assign x_pos_h_l = col[9:3] - 7'd13;
    assign x_pos_h_m = col[9:3] - 7'd1;

    VGA_Segment_Check vsc_c_l (.x_pos(x_pos_c_l), .ss_out(disp_curr_ss_lsd), .in_box(in_box_c_l), .*);
    VGA_Segment_Check vsc_c_m (.x_pos(x_pos_c_m), .ss_out(disp_curr_ss_msd), .in_box(in_box_c_m), .*);
    VGA_Segment_Check vsc_h_l (.x_pos(x_pos_h_l), .ss_out(disp_high_ss_lsd), .in_box(in_box_h_l), .*);
    VGA_Segment_Check vsc_h_m (.x_pos(x_pos_h_m), .ss_out(disp_high_ss_msd), .in_box(in_box_h_m), .*);

    // signal indicating if a digit is being displayed or not -- supposed to display
    // a segment based on score & in the corresponding segment based on vga row/col
    logic is_curr_score_lsd, is_curr_score_msd, is_high_score_lsd, is_high_score_msd;

    assign is_curr_score_lsd = |(curr_ss_lsd & disp_curr_ss_lsd);
    assign is_curr_score_msd = |(curr_ss_msd & disp_curr_ss_msd);
    assign is_high_score_lsd = |(high_ss_lsd & disp_high_ss_lsd);
    assign is_high_score_msd = |(high_ss_msd & disp_high_ss_msd);

    logic is_curr_score, is_high_score;
    assign is_curr_score = is_curr_score_lsd | is_curr_score_msd;
    assign is_high_score = is_high_score_lsd | is_high_score_msd;

    // make sure in the right y-range too so numbers don't wrap around lol
    assign is_score = (in_score_box_row) & (is_curr_score | is_high_score);

endmodule : Score_Color


// Handle all the coloring stuff for the main gameboard (snake, fruit)
// Also handle score digit coloring while we're here
module Color_Gameboard(
    input logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data,
    input logic [$clog2(MAX_SNAKE_SIZE):0] snake_length,
    input logic [5:0] fruit_pos,
    input logic [9:0] row, col,
    input logic [7:0] curr_score, high_score,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output logic is_snake,
    output logic [MAX_SNAKE_SIZE - 1:0] snake_valid
);

    logic is_score;
    logic [11:0] score_color;
    Score_Color sc (.curr_score(curr_score), .high_score(high_score),
                    .row(row), .col(col), .is_score(is_score));

    assign score_color = (snake_length == MAX_SNAKE_SIZE) ? {4'hf, 4'h0, 4'hf} : {4'hf, 4'hf, 4'hf};

    logic [9:0] game_row, game_col;
    logic vga_in_grid;

    assign vga_in_grid = (row >= 10'd112) & (row < 10'd368) & (col >= 10'd192) & (col < 10'd448);

    // subtract grid origin offsets
    assign game_row = row - 10'd112;
    assign game_col = col - 10'd192;

    // get which tile the VGA row and col are on (integer div by pixel size=32 since 8x8 grid)
    logic [2:0] tile_row, tile_col;
    assign tile_row = game_row >> 10'd5; // 0 -> 7
    assign tile_col = game_col >> 10'd5;

    logic display_snake;
    assign is_snake = display_snake;
    logic [MAX_SNAKE_SIZE - 1:0] in_snake;
    
    // thermometer encoding of snake_length to get a mask for the snake_data
    assign snake_valid = ('1) >> (($clog2(MAX_SNAKE_SIZE) + 1)'(MAX_SNAKE_SIZE) - snake_length);
    
    // figure out if we're supposed to display some snek or not, and what type of snek
    genvar i;
    generate
        for(i = 0; i < MAX_SNAKE_SIZE; i++) begin
            assign in_snake[i] = (snake_data[i][5:3] == tile_row) & (snake_data[i][2:0] == tile_col) & (snake_valid[i]);
        end
    endgenerate

    assign display_snake = |in_snake;

    // convert one-hot in_snake to index to find which snake tile number is being displayed
    // for use in the rainbow coloring
    logic [$clog2(MAX_SNAKE_SIZE) - 1:0] curr_snake_idx;
    always_comb begin
        curr_snake_idx = '0;
        for(int k = 0; k < MAX_SNAKE_SIZE; k++) begin
            if(in_snake[k]) begin
                curr_snake_idx = k[$clog2(MAX_SNAKE_SIZE) - 1:0];
            end
        end
    end

    // check if current vga tile is on fruit's location
    logic display_fruit;
    assign display_fruit = (tile_row == fruit_pos[5:3]) && (tile_col == fruit_pos[2:0]);

    logic [11:0] snake_color, fruit_color;

    // RAINBOWWWW
    logic [5:0][11:0] colors;
    assign colors[0] = {4'hf, 4'h0, 4'h0}; // red 
    assign colors[1] = {4'hf, 4'h2, 4'h0}; // orange
    assign colors[2] = {4'hf, 4'hf, 4'h0}; // yellow
    assign colors[3] = {4'h0, 4'hf, 4'h1}; // green
    assign colors[4] = {4'h0, 4'h4, 4'hf}; // blue
    assign colors[5] = {4'h2, 4'h0, 4'hf}; // violet


    // make sure MAX_SNAKE_SIZE <= 32
    logic [4:0] res24, res12, res6;
    // subtract tree to do curr_snake_idx % 6
    always_comb begin
        res24 = (curr_snake_idx >= 5'd24) ? curr_snake_idx - 5'd24 : curr_snake_idx;
        res12 = (res24 >= 5'd12) ? res24 - 5'd12 : res24;
        res6 = (res12 >= 5'd6) ? res12 - 5'd6 : res12;
    end

    assign snake_color = colors[res6[2:0]];
    assign fruit_color = {4'hf, 4'hf, 4'hf}; // SNAKE EATS (WHITE) EGG

    // Pick which color based on what's located at the current tile
    always_comb begin
        // default black background
        {VGA_R, VGA_G, VGA_B} = '0;
        
        // white game board outline
        if((game_row == 10'd0) | (game_row == 10'd256) | (game_col == 10'd0) | (game_col == 10'd256)) begin
            {VGA_R, VGA_G, VGA_B} = '1;
        end
        else if(is_score) begin
            {VGA_R, VGA_G, VGA_B} = score_color;
        end
        else if(vga_in_grid) begin
            // just green snake for now
            if(display_snake) begin
                {VGA_R, VGA_G, VGA_B} = snake_color;
            end

            else if(display_fruit) begin
                {VGA_R, VGA_G, VGA_B} = fruit_color;
            end
        end
        // black background
        else begin
            {VGA_R, VGA_G, VGA_B} = '0;
        end
    end

endmodule : Color_Gameboard