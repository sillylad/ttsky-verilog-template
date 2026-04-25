`default_nettype none

// Snake tile style - convention is the direction in the name is the side
// where the snake tile connects to another tile
// e.g. LEFT_RIGHT is just a horizontal piece
typedef enum logic [3:0]   {UP_RIGHT, UP_LEFT, DOWN_RIGHT, DOWN_LEFT,
                            UP_TAIL, LEFT_TAIL, RIGHT_TAIL, DOWN_TAIL,
                            UP_HEAD, LEFT_HEAD, RIGHT_HEAD, DOWN_HEAD,
                            UP_DOWN, LEFT_RIGHT,
                            EMPTY} snake_style_t;

typedef enum logic [1:0] {MOVE_UP, MOVE_LEFT, MOVE_RIGHT, MOVE_DOWN} snake_move;

localparam MAX_SNAKE_SIZE = 12;
localparam MAX_SNAKE_SIZE_BCD = 8'h12;
localparam MAX_GAME_SCORE = 7'd99;

module Snake (
    input logic clk, rst_n,
    input logic game_clk,
    input logic start_game,
    input logic [3:0] dir,
    input logic [9:0] row, col,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output snake_move curr_dir,
    output logic [$clog2(MAX_SNAKE_SIZE) : 0] snake_length,
    output logic [5:0] head_pos,
    output logic is_snake,
    output logic [3:0] debug_nc
);
    // snake is moving always so dir should be sticky
    logic [3:0] sticky_dir;
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            sticky_dir <= 4'b1000; // move right
        end
        // also reset dir when ded
        else if(collision) begin
            sticky_dir <= 4'b1000;
        end
        else begin
            // only update sticky_dir if at least one button is pressed
            if(dir) begin
                sticky_dir <= dir;
            end
            // no button pressed so hold old set of buttons
            else begin
                sticky_dir <= sticky_dir;
            end
        end
    end

    // MAX_SNAKE_SIZE-element shift register for snake motion tracking
    logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data;
    logic [MAX_SNAKE_SIZE - 1:0] snake_valid;
    logic snake_init, grow, snake_enable, collision;
    logic [5:0] new_head;
    assign debug_nc = {snake_enable, (snake_init & game_clk), (start_game & game_clk), 1'b0};

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
            endcase
        end
    end

    assign grow = (new_head == fruit_pos);
    // collision when new_head wraps around the board one way or another
    // Stores the current snake data and updates the snake position as needed
    // Output snake_data array for use by other blocks
    Snake_Register sreg (.clk(clk), .rst_n(rst_n), .game_clk(game_clk),
                    .snake_enable(snake_enable), .snake_init(snake_init),
                    .dir(sticky_dir), .grow(grow),
                    .snake_data(snake_data), .snake_length(snake_length), .snake_valid(snake_valid),
                    .new_head(new_head), .curr_dir(curr_dir), .collision(collision));

    assign head_pos = snake_data[0]; // pull out of snake_register for debug
    
    // Fruit
    logic [5:0] fruit_pos;
    logic grow_posedge;
    PRNG fruit_gen (.clk(clk), .game_clk(game_clk), .rst_n(rst_n),
                    .snake_data(snake_data), .snake_valid(snake_valid),
                    .grow(grow), .fruit_pos(fruit_pos), .grow_posedge(grow_posedge));

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
                high_score <= (curr_score > high_score) ? curr_score : high_score;
                // reset current score cuz ded
                curr_score <= '0;
            end
            // else if(grow_posedge) begin
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
    output logic collision,
    output snake_move curr_dir
);

    snake_move decoded_dir, fast_dir;
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
        else begin
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
    assign wall_collision_all[0] = (curr_dir == MOVE_UP) & (snake_data[0][5:3] == 3'd0) & (new_head[5:3] == 3'd7);
    assign wall_collision_all[1] = (curr_dir == MOVE_DOWN) & (snake_data[0][5:3] == 3'd7) & (new_head[5:3] == 3'd0);
    assign wall_collision_all[2] = (curr_dir == MOVE_LEFT) & (snake_data[0][2:0] == 3'd0) & (new_head[2:0] == 3'd7);
    assign wall_collision_all[3] = (curr_dir == MOVE_RIGHT) & (snake_data[0][2:0] == 3'd7) & (new_head[2:0] == 3'd0);

    assign wall_collision = (|wall_collision_all) & snake_enable;


    logic [MAX_SNAKE_SIZE - 1:0] head_on_snake;
    genvar i;
    generate
        for(i = 0; i < MAX_SNAKE_SIZE; i++) begin
            assign head_on_snake[i] =  (snake_data[i][5:3] == new_head[5:3]) & 
                                        (snake_data[i][2:0] == new_head[2:0]) & 
                                        (snake_valid[i]);
        end
    endgenerate

    assign self_collision = (|head_on_snake) & snake_enable;

    assign collision = wall_collision | self_collision;
    // assign collision = 1'b0;
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
// Generate "random" value between 0 -> MAX_SNAKE_SIZE - 1 (MAX_SNAKE_SIZE tiles) to get next fruit pos
module PRNG (
    input logic clk, rst_n,
    input logic game_clk,
    input logic [MAX_SNAKE_SIZE - 1:0][5:0] snake_data,
    input logic [MAX_SNAKE_SIZE - 1:0] snake_valid,
    input logic grow,
    output logic [5:0] fruit_pos,
    output logic grow_posedge
);

    logic valid_fruit, shift, get_new_pos, grow_prev, grow_posedge;

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            grow_prev <= 1'b0;
        end
        else begin
            grow_prev <= grow;
        end
    end

    assign grow_posedge = grow & ~grow_prev;

    logic [MAX_SNAKE_SIZE - 1:0] fruit_on_snake;

    // spin lfsr on faster clock so it can resolve in time
    logic [5:0] seed, lfsr_out;
    assign seed = 6'b1;
    LFSR_6_BIT lfsr(.clk(clk), .rst_n(rst_n), .shift(shift), .seed(seed),
                    .lfsr_out(lfsr_out));

    assign shift = ~valid_fruit & get_new_pos;

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            get_new_pos <= 1'b0;
        end
        // trigger new fruit position search
        else if(grow_posedge) begin
            get_new_pos <= 1'b1;
        end
        // stop searching when you found a valid fruit
        else if(valid_fruit & game_clk & get_new_pos) begin
            get_new_pos <= 1'b0;
        end
    end

    // update visible fruit_pos only when a valid tile has been found (max MAX_SNAKE_SIZE - 1 clocks)
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            fruit_pos <= {3'd3, 3'd6};
        end
        // update visible fruit on game clock only (high for 1 clock only)
        else if(game_clk & valid_fruit & get_new_pos) begin
            fruit_pos <= lfsr_out;
        end
    end

    // check if the proposed fruit tile is on top of the snake
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

module LFSR_6_BIT(
    input logic clk, rst_n, shift,
    input logic [5:0] seed,
    output logic [5:0] lfsr_out
);

    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            // reset lfsr to seed, but make sure seed isn't 0 else lfsr will lock
            lfsr_out <= (seed == '0) ? 6'b1 : seed;
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

module VGA_Segment_Check(
    input logic [9:0] row, col,
    input logic [9:0] x_offset,
    output logic [6:0] ss_out
);

    logic left_lane, right_lane, middle_lane;
    logic top_row, middle_row, bottom_row, top_half, bottom_half;
    logic in_score_box;

    logic [9:0] x_pos, y_pos;

    assign x_pos = col - x_offset;
    assign y_pos = row - 10'd144;

    assign left_lane = (x_pos < 10'd8);
    assign right_lane = (x_pos >= 10'd72) & (x_pos < 10'd80);
    assign middle_lane = (x_pos >= 10'd8) & (x_pos < 10'd72);

    assign top_row = (y_pos < 10'd8);
    assign middle_row = (y_pos >= 10'd92) & (y_pos < 10'd100);
    assign bottom_row = (y_pos >= 10'd184) & (y_pos < 10'd192);
    assign top_half = (y_pos < 10'd100);
    assign bottom_half = (y_pos >= 10'd92);

    logic [6:0] ss_out_init;

    // {a, b, c, d, e, f, g}
    assign ss_out_init[6] = middle_lane & top_row;
    assign ss_out_init[5] = right_lane & top_half;
    assign ss_out_init[4] = right_lane & bottom_half;
    assign ss_out_init[3] = middle_lane & bottom_row;
    assign ss_out_init[2] = left_lane & bottom_half;
    assign ss_out_init[1] = left_lane & top_half;
    assign ss_out_init[0] = middle_lane & middle_row;

    assign in_score_box = (row >= 10'd144) & (row < 10'd336) &
                          (col >= x_offset) & (col < (x_offset + 10'd80));

    assign ss_out = (in_score_box) ? ss_out_init : '0;

endmodule : VGA_Segment_Check

module Score_Color(
    input logic [7:0] curr_score, high_score,
    input logic [9:0] row, col,
    output logic is_score
);
    localparam score_box_y_offset = 144; // 112 + 32
    localparam curr_score_x_offset = 0;
    localparam high_score_x_offset = 448;

    // which segments we are supposed to display
    logic [6:0] curr_ss_lsd, curr_ss_msd, high_ss_lsd, high_ss_msd;
    // which segment are we in right now based on vga row/col
    logic [6:0] disp_curr_ss_lsd, disp_curr_ss_msd, disp_high_ss_lsd, disp_high_ss_msd;

    BCD_to_SS bts_curr_lsd (.value(curr_score[3:0]), .ss_value(curr_ss_lsd));
    BCD_to_SS bts_curr_msd (.value(curr_score[7:4]), .ss_value(curr_ss_msd));
    BCD_to_SS bts_high_lsd (.value(high_score[3:0]), .ss_value(high_ss_lsd));
    BCD_to_SS bts_high_msd (.value(high_score[7:4]), .ss_value(high_ss_msd));

    VGA_Segment_Check vsc_c_l (.row(row), .col(col), .x_offset(10'd552), .ss_out(disp_curr_ss_lsd));
    VGA_Segment_Check vsc_c_m (.row(row), .col(col), .x_offset(10'd456), .ss_out(disp_curr_ss_msd));
    VGA_Segment_Check vsc_h_l (.row(row), .col(col), .x_offset(10'd104), .ss_out(disp_high_ss_lsd));
    VGA_Segment_Check vsc_h_m (.row(row), .col(col), .x_offset(10'd8), .ss_out(disp_high_ss_msd));

    logic is_curr_score_lsd, is_curr_score_msd, is_high_score_lsd, is_high_score_msd;

    assign is_curr_score_lsd = |(curr_ss_lsd & disp_curr_ss_lsd);
    assign is_curr_score_msd = |(curr_ss_msd & disp_curr_ss_msd);
    assign is_high_score_lsd = |(high_ss_lsd & disp_high_ss_lsd);
    assign is_high_score_msd = |(high_ss_msd & disp_high_ss_msd);

    logic is_curr_score, is_high_score;
    assign is_curr_score = is_curr_score_lsd | is_curr_score_msd;
    assign is_high_score = is_high_score_lsd | is_high_score_msd;

    logic in_score_box;
    assign is_score = (is_curr_score | is_high_score);

endmodule : Score_Color


// Handle all the coloring stuff for the gameboard (snake, fruit)
// Also handle digit coloring while we're here
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
    logic [5:0] curr_snake_idx;
    always_comb begin
        curr_snake_idx = '0;
        for(int k = 0; k < MAX_SNAKE_SIZE; k++) begin
            if(in_snake[k]) begin
                curr_snake_idx = k[5:0];
            end
        end
    end

    logic display_fruit;
    assign display_fruit = (tile_row == fruit_pos[5:3]) && (tile_col == fruit_pos[2:0]);

    logic [11:0] snake_color, fruit_color;
    
    logic [5:0][11:0] colors;
    assign colors[0] = {4'hf, 4'h0, 4'h0}; // red 
    assign colors[1] = {4'hf, 4'h2, 4'h0}; // orange
    assign colors[2] = {4'hf, 4'hf, 4'h0}; // yellow
    assign colors[3] = {4'h0, 4'hf, 4'h1}; // green
    assign colors[4] = {4'h0, 4'h4, 4'hf}; // blue
    assign colors[5] = {4'h2, 4'h0, 4'hf}; // violet


    logic [5:0] res48, res24, res12, res6;
    // subtract tree to do % 6
    always_comb begin
        res48 = (curr_snake_idx >= 6'd48) ? curr_snake_idx - 6'd48 : curr_snake_idx;
        res24 = (res48 >= 6'd24) ? res48 - 6'd24 : res48;
        res12 = (res24 >= 6'd12) ? res24 - 6'd12 : res24;
        res6 = (res12 >= 6'd6) ? res12 - 6'd6 : res12;
    end

    assign snake_color = colors[res6[2:0]];
    assign fruit_color = {4'hf, 4'hf, 4'hf}; // SNAKE EATS EGG

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

// // Logic for getting the snake styles right (color is handled in Color_Gameboard
// // still, this is just for deciding between snake body color vs. black background)
// module Snake_Tiles(
//     input logic [9:0] game_row, game_col,
//     input logic [2:0] tile_row, tile_col,
//     output logic RGB_UP_RIGHT, RGB_UP_LEFT, RGB_DOWN_RIGHT, RGB_DOWN_LEFT,
//                  RGB_UP_TAIL, RGB_LEFT_TAIL, RGB_RIGHT_TAIL, RGB_DOWN_TAIL,
//                  RGB_UP_HEAD, RGB_LEFT_HEAD, RGB_RIGHT_HEAD, RGB_DOWN_HEAD,
//                  RGB_UP_DOWN, RGB_LEFT_RIGHT
// );

//     logic [5:0] pixel_row, pixel_col;

//     // map global grid coordinate to just one tile's pixels
//     // (pixel_row, pixel_col) is in [0, MAX_SNAKE_SIZE - 1] x [0, MAX_SNAKE_SIZE - 1]
//     assign pixel_row = game_row - (tile_row << 10'd5);
//     assign pixel_col = game_col - (tile_col << 10'd5);

//     logic row_in_center, col_in_center;
//     assign row_in_center = (6'd4 <= pixel_row) & (pixel_row <= 6'd27);
//     assign col_in_center = (6'd4 <= pixel_col) & (pixel_col <= 6'd27);

//     logic row_in_top, row_in_bottom, col_in_left, col_in_right;
//     assign row_in_top = (pixel_row <= 6'd3);
//     assign row_in_bottom = (6'd28 <= pixel_row) & (pixel_row <= 6'd31);
//     assign col_in_left = (pixel_col <= 6'd3);
//     assign col_in_right = (6'd28 <= pixel_col) & (pixel_col <= 6'd31);
//     // most snake tiles have the middle 48x48 pixels filled with snake (except
//     // head cuz of the eyes)
//     logic center_square;
//     assign center_square = row_in_center & col_in_center;

//     logic top_seg, bottom_seg, left_seg, right_seg;
//     assign top_seg = (row_in_top & col_in_center);
//     assign bottom_seg = (row_in_bottom & col_in_center);
//     assign left_seg = (col_in_left & row_in_center);
//     assign right_seg = (col_in_right & row_in_center);

//     logic top_eye_lane, bottom_eye_lane, left_eye_lane, right_eye_lane;
//     assign top_eye_lane = (pixel_row >= 6'd8) & (pixel_row <= 6'd11);
//     assign bottom_eye_lane = (pixel_row >= 6'd20) & (pixel_row <= 6'd23);
//     assign left_eye_lane = (pixel_col >= 6'd8) & (pixel_col <= 6'd11);
//     assign right_eye_lane = (pixel_col >= 6'd20) & (pixel_col <= 6'd23);

//     logic top_left_eye, top_right_eye, bottom_left_eye, bottom_right_eye;
//     assign top_left_eye = top_eye_lane & left_eye_lane;
//     assign top_right_eye = top_eye_lane & right_eye_lane;
//     assign bottom_left_eye = bottom_eye_lane & left_eye_lane;
//     assign bottom_right_eye = bottom_eye_lane & right_eye_lane;

//     logic up_head_eyes, left_head_eyes, right_head_eyes, down_head_eyes;
//     assign up_head_eyes = (bottom_left_eye | bottom_right_eye);
//     assign left_head_eyes = (top_right_eye | bottom_right_eye);
//     assign right_head_eyes = (top_left_eye | bottom_left_eye);
//     assign down_head_eyes = (top_left_eye | top_right_eye);


//     assign RGB_UP_RIGHT   = center_square | top_seg | right_seg;
//     assign RGB_UP_LEFT    = center_square | top_seg | left_seg;
//     assign RGB_DOWN_RIGHT = center_square | bottom_seg | right_seg;
//     assign RGB_DOWN_LEFT  = center_square | bottom_seg | left_seg;

//     assign RGB_UP_TAIL    = center_square | top_seg;
//     assign RGB_LEFT_TAIL  = center_square | left_seg;
//     assign RGB_RIGHT_TAIL = center_square | right_seg;
//     assign RGB_DOWN_TAIL  = center_square | bottom_seg;

//     assign RGB_UP_HEAD    = top_seg | (center_square & ~up_head_eyes);
//     assign RGB_LEFT_HEAD  = left_seg | (center_square & ~left_head_eyes);
//     assign RGB_RIGHT_HEAD = right_seg | (center_square & ~right_head_eyes);
//     assign RGB_DOWN_HEAD  = bottom_seg | (center_square & ~down_head_eyes);

//     assign RGB_UP_DOWN    = center_square | top_seg | bottom_seg;
//     assign RGB_LEFT_RIGHT = center_square | left_seg | right_seg;

// endmodule : Snake_Tiles