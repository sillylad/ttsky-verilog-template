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


module Snake (
    input logic clk, rst_n,
    input logic game_clk,
    input logic start_game,
    input logic [3:0] dir,
    input logic [9:0] row, col,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output logic buzz,
    output snake_move curr_dir,
    output logic [6:0] snake_length,
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

    // 64-element shift register for snake motion tracking
    logic [63:0][5:0] snake_data;
    logic [63:0] snake_valid;
    logic snake_init, grow, snake_enable, collision;
    logic [5:0] new_head;

    assign snake_init = 1'b0;
    
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            snake_enable <= 1'b0;
        end
        else begin
            snake_enable <= (start_game) ? ~snake_enable : snake_enable;
        end
    end
    // assign snake_enable = 1'b1;
    assign grow = (new_head == fruit_pos);
    // collision when new_head wraps around the board one way or another
    // assign collision = (
    // Stores the current snake data and updates the snake position as needed
    // Output snake_data array for use by other blocks
    Snake_Register sreg (.clk(clk), .rst_n(rst_n), .game_clk(game_clk),
                    .snake_enable(snake_enable), .snake_init(snake_init),
                    .dir(sticky_dir), .start_game(start_game), .grow(grow),
                    .snake_data(snake_data), .snake_length(snake_length),
                    .new_head(new_head), .curr_dir(curr_dir));

    assign head_pos = snake_data[0]; // pull out of snake_register for debug
    
    // Fruit
    logic [5:0] fruit_pos;
    PRNG fruit_gen (.clk(clk), .game_clk(game_clk), .rst_n(rst_n),
                    .snake_data(snake_data), .snake_valid(snake_valid),
                    .grow(grow), .fruit_pos(fruit_pos));

    // Scoring
    logic [5:0] high_score, curr_score;
    always_ff @(posedge clk, negedge rst_n) begin
        if(~rst_n) begin
            curr_score <= '0;
            high_score <= '0;
        end
        else begin
            if(grow) begin
                curr_score <= curr_score + 1'b1;
            end
        end
    end

    // Audio

    // Color
    Color_Gameboard cgb(.snake_data(snake_data),
                        .snake_length(snake_length),
                        .snake_valid(snake_valid),
                        .fruit_pos(fruit_pos),
                        .row(row), .col(col), .is_snake(is_snake), .debug_nc(debug_nc), .*);

    // Overall Game Handling FSM

endmodule : Snake


// Update the snake shift register (location of the snake) and 8x8 grid of 
// snake tiles
module Snake_Register (
    input logic clk, rst_n, game_clk,
    input logic [3:0] dir,
    input logic start_game, grow, snake_enable, snake_init,
    output logic [63:0][5:0] snake_data, // shift register values
    output logic [6:0] snake_length,
    output logic [5:0] new_head,
    output snake_move curr_dir
);

    snake_move decoded_dir, fast_dir;

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
            curr_dir <= fast_dir;
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
        snake_length <= 7'd3;

        // Initial snake shift register = horizontal snake facing left
        for(int i = 0; i < 64; i++) begin
            // set the initial head of the snake
            if(i == 0) begin
                snake_data[i] <= {3'd3, 3'd3};
            end
            else if(i == 1) begin
                snake_data[i] <= {3'd3, 3'd2};
            end
            // set the initial tail of the snake
            else if(i == 2) begin
                snake_data[i] <= {3'd3, 3'd1};
            end
            else begin
                snake_data[i] <= '0;
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

    // Update snake register
    always_ff @(posedge clk, negedge rst_n) begin
        // reset snake in the middle of the board
        if(~rst_n) begin
            initialize_snake();
        end
        else if(snake_init) begin
            initialize_snake();
        end
        // else begin
        else if(game_clk) begin
            // Only move the snake if a game has commenced
            if(snake_enable) begin
                // Snake has collided with apple, replace head and increment length
                if(grow) begin
                    snake_length <= snake_length + 7'd1;
                    // Update tiles
                    for(int i = 63; i > 0; i--) begin
                        snake_data[i] <= snake_data[i-1];
                    end
                    snake_data[0] <= new_head;
                end
                // Snake keeps moving
                else begin
                    for(int i = 63; i > 0; i--) begin
                        snake_data[i] <= snake_data[i-1];
                    end
                    snake_data[0] <= new_head;
                end
            end
        end
        else begin
            snake_data <= snake_data;
            snake_length <= snake_length;
        end
    end
    

endmodule : Snake_Register

// 6-bit PRNG
// Generate "random" value between 0 -> 63 (64 tiles) to get next fruit pos
module PRNG (
    input logic clk, rst_n,
    input logic game_clk,
    input logic [63:0][5:0] snake_data,
    input logic [63:0] snake_valid,
    input logic grow,
    output logic [5:0] fruit_pos
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

    logic [63:0] fruit_on_snake;

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

    // update visible fruit_pos only when a valid tile has been found (max 63 clocks)
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
        for(i = 0; i < 64; i++) begin
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


// Handle all the coloring stuff for the gameboard (snake, fruit)
module Color_Gameboard(
    input logic [63:0][5:0] snake_data,
    input logic [6:0] snake_length,
    input logic [5:0] fruit_pos,
    input logic [9:0] row, col,
    output logic [3:0] VGA_R, VGA_G, VGA_B,
    output logic is_snake,
    output logic [63:0] snake_valid,
    output logic [3:0] debug_nc
);
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
    logic [63:0] in_snake;

    // logic RGB_UP_RIGHT, RGB_UP_LEFT, RGB_DOWN_RIGHT, RGB_DOWN_LEFT,
    //       RGB_UP_TAIL, RGB_LEFT_TAIL, RGB_RIGHT_TAIL, RGB_DOWN_TAIL,
    //       RGB_UP_HEAD, RGB_LEFT_HEAD, RGB_RIGHT_HEAD, RGB_DOWN_HEAD,
    //       RGB_UP_DOWN, RGB_LEFT_RIGHT;

    // Snake_Tiles sts(.game_row(game_row), .game_col(game_col),
    //                 .tile_row(tile_row), .tile_col(tile_col),
    //                 .RGB_UP_RIGHT(RGB_UP_RIGHT), .RGB_UP_LEFT(RGB_UP_LEFT),
    //                 .RGB_DOWN_RIGHT(RGB_DOWN_RIGHT), .RGB_DOWN_LEFT(RGB_DOWN_LEFT),
    //                 .RGB_UP_TAIL(RGB_UP_TAIL), .RGB_LEFT_TAIL(RGB_LEFT_TAIL),
    //                 .RGB_RIGHT_TAIL(RGB_RIGHT_TAIL), .RGB_DOWN_TAIL(RGB_DOWN_TAIL),
    //                 .RGB_UP_HEAD(RGB_UP_HEAD), .RGB_LEFT_HEAD(RGB_LEFT_HEAD),
    //                 .RGB_RIGHT_HEAD(RGB_RIGHT_HEAD), .RGB_DOWN_HEAD(RGB_DOWN_HEAD),
    //                 .RGB_UP_DOWN(RGB_UP_DOWN), .RGB_LEFT_RIGHT(RGB_LEFT_RIGHT));
    
    // thermometer encoding of snake_length to get a mask for the snake_data
    // logic [63:0] snake_valid;
    logic [63:0] ones_mask;

    assign ones_mask = '1;
    assign snake_valid = ones_mask >> (7'd64 - snake_length);

    // snake_style_t [63:0] style;
    // [down, up, left, right]
    // logic [63:0][3:0] next_coord;
    // logic [63:0][3:0] prev_coord;
    
    // figure out if we're supposed to display some snek or not, and what type of snek
    genvar i;
    generate
        for(i = 0; i < 64; i++) begin
            assign in_snake[i] = (snake_data[i][5:3] == tile_row) & (snake_data[i][2:0] == tile_col) & (snake_valid[i]);
            
            // if(i < 63) begin
            //     // same row, next tile is to the right
            //     assign next_coord[i][0] = (snake_data[i][5:3] == snake_data[i+1][5:3]) & ((snake_data[i][2:0] + 3'd1 == snake_data[i+1][2:0]));
            //     // next tile is to the left
            //     assign next_coord[i][1] = (snake_data[i][5:3] == snake_data[i+1][5:3]) & ((snake_data[i][2:0] - 3'd1) == snake_data[i+1][2:0]);
            //     // next tile is above
            //     assign next_coord[i][2] = ((snake_data[i][5:3] - 3'd1) == snake_data[i+1][5:3]) & (snake_data[i][2:0] == snake_data[i+1][2:0]);
            //     // next tile is below
            //     assign next_coord[i][3] = ((snake_data[i][5:3] + 3'd1) == snake_data[i+1][5:3]) & (snake_data[i][2:0] == snake_data[i+1][2:0]);
            // end
            // else begin
            //     assign next_coord[i] = '0;
            // end
            // if(i > 0) begin
            //     // previous tile is to the right
            //     assign prev_coord[i][0] = (snake_data[i][5:3] == snake_data[i-1][5:3]) & ((snake_data[i][2:0] + 3'd1) == snake_data[i-1][2:0]);
            //     // prev tile is to the left
            //     assign prev_coord[i][1] = (snake_data[i][5:3] == snake_data[i-1][5:3]) & ((snake_data[i][2:0] - 3'd1) == snake_data[i-1][2:0]);
            //     // prev tile above
            //     assign prev_coord[i][2] = ((snake_data[i][5:3] - 3'd1) == snake_data[i-1][5:3]) & (snake_data[i][2:0] == snake_data[i-1][2:0]);
            //     // prev tile below
            //     assign prev_coord[i][3] = ((snake_data[i][5:3] + 3'd1) == snake_data[i-1][5:3]) & (snake_data[i][2:0] == snake_data[i-1][2:0]);
            // end
            // else begin
            //     assign prev_coord[i] = '0;
            // end
        end
    endgenerate

    // always_comb begin
    //     for(int j = 0; j < 64; j++) begin
    //         // SNAKE HEAD
    //         if(j == 0) begin
    //             case(next_coord[0])
    //                 // [down, up, left, right]
    //                 4'b1000: style[0] = DOWN_HEAD;
    //                 4'b0100: style[0] = UP_HEAD;
    //                 4'b0010: style[0] = LEFT_HEAD;
    //                 4'b0001: style[0] = RIGHT_HEAD;
    //                 default: style[0] = EMPTY;
    //             endcase
    //         end
    //         // tail piece
    //         else if(j == 63 | ((j < 63) & ~snake_valid[j+1])) begin
    //             case(prev_coord[j])
    //                 4'b1000: style[j] = DOWN_TAIL;
    //                 4'b0100: style[j] = UP_TAIL;
    //                 4'b0010: style[j] = LEFT_TAIL;
    //                 4'b0001: style[j] = RIGHT_TAIL;
    //                 default: style[j] = EMPTY;
    //             endcase
    //         end
    //         // there exists some snake after this tile
    //         else if(j < 63) begin
    //             case(next_coord[j] | prev_coord[j])
    //                 // connecting pieces on top and bottom side
    //                 4'b1100: style[j] = UP_DOWN;
    //                 // bottom and left
    //                 4'b1010: style[j] = DOWN_LEFT;
    //                 // bottom and right
    //                 4'b1001: style[j] = DOWN_RIGHT;
    //                 // up and left
    //                 4'b0110: style[j] = UP_LEFT;
    //                 // up and right
    //                 4'b0101: style[j] = UP_RIGHT;
    //                 // left and right
    //                 4'b0011: style[j] = LEFT_RIGHT;
    //                 default: style[j] = EMPTY;
    //             endcase
    //         end
    //         // default just in case
    //         else begin
    //             style[j] = EMPTY;
    //         end
    //     end
    // end

    // assign debug_nc = prev_coord[2];

    assign display_snake = |in_snake;

    // snake_style_t curr_style;
    // convert one-hot in_snake to index to find which snake tile number is being displayed
    logic [5:0] curr_snake_idx;
    always_comb begin
        curr_snake_idx = '0;
        for(int i = 0; i < 64; i++) begin
            if(in_snake[i]) begin
                curr_snake_idx = i[5:0];
            end
        end
    end

    // assign curr_style = style[curr_snake_idx];

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


    logic [2:0] color_idx;
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
        else if(vga_in_grid) begin
            // just green snake for now
            if(display_snake) begin
                {VGA_R, VGA_G, VGA_B} = snake_color;
                // VGA_R = '0;
                // VGA_G = '1;
                // VGA_B = '0;
                // case (curr_style)
                //     UP_RIGHT: {VGA_R, VGA_G, VGA_B} = (RGB_UP_RIGHT) ? snake_color : '0;
                //     UP_LEFT: {VGA_R, VGA_G, VGA_B} = (RGB_UP_LEFT) ? snake_color : '0;
                //     DOWN_RIGHT: {VGA_R, VGA_G, VGA_B} = (RGB_DOWN_RIGHT) ? snake_color : '0;
                //     DOWN_LEFT: {VGA_R, VGA_G, VGA_B} = (RGB_DOWN_LEFT) ? snake_color : '0;
                //     UP_TAIL: {VGA_R, VGA_G, VGA_B} = (RGB_UP_TAIL) ? snake_color : '0;
                //     LEFT_TAIL: {VGA_R, VGA_G, VGA_B} = (RGB_LEFT_TAIL) ? snake_color : '0;
                //     RIGHT_TAIL: {VGA_R, VGA_G, VGA_B} = (RGB_RIGHT_TAIL) ? snake_color : '0;
                //     DOWN_TAIL: {VGA_R, VGA_G, VGA_B} = (RGB_DOWN_TAIL) ? snake_color : '0;
                //     UP_HEAD: {VGA_R, VGA_G, VGA_B} = (RGB_UP_HEAD) ? snake_color : '0;
                //     LEFT_HEAD: {VGA_R, VGA_G, VGA_B} = (RGB_LEFT_HEAD) ? snake_color : '0;
                //     RIGHT_HEAD: {VGA_R, VGA_G, VGA_B} = (RGB_RIGHT_HEAD) ? snake_color : '0;
                //     DOWN_HEAD: {VGA_R, VGA_G, VGA_B} = (RGB_DOWN_HEAD) ? snake_color : '0;
                //     UP_DOWN: {VGA_R, VGA_G, VGA_B} = (RGB_UP_DOWN) ? snake_color : '0;
                //     LEFT_RIGHT: {VGA_R, VGA_G, VGA_B} = (RGB_LEFT_RIGHT) ? snake_color : '0;
                //     EMPTY: {VGA_R, VGA_G, VGA_B} = {4'b0, 4'b0, 4'hf};
                //     default: {VGA_R, VGA_G, VGA_B} = '0; // default black bg
                // endcase
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

// Logic for getting the snake styles right (color is handled in Color_Gameboard
// still, this is just for deciding between snake body color vs. black background)
module Snake_Tiles(
    input logic [9:0] game_row, game_col,
    input logic [2:0] tile_row, tile_col,
    output logic RGB_UP_RIGHT, RGB_UP_LEFT, RGB_DOWN_RIGHT, RGB_DOWN_LEFT,
                 RGB_UP_TAIL, RGB_LEFT_TAIL, RGB_RIGHT_TAIL, RGB_DOWN_TAIL,
                 RGB_UP_HEAD, RGB_LEFT_HEAD, RGB_RIGHT_HEAD, RGB_DOWN_HEAD,
                 RGB_UP_DOWN, RGB_LEFT_RIGHT
);

    logic [5:0] pixel_row, pixel_col;

    // map global grid coordinate to just one tile's pixels
    // (pixel_row, pixel_col) is in [0, 63] x [0, 63]
    assign pixel_row = game_row - (tile_row << 10'd5);
    assign pixel_col = game_col - (tile_col << 10'd5);

    logic row_in_center, col_in_center;
    assign row_in_center = (6'd4 <= pixel_row) & (pixel_row <= 6'd27);
    assign col_in_center = (6'd4 <= pixel_col) & (pixel_col <= 6'd27);

    logic row_in_top, row_in_bottom, col_in_left, col_in_right;
    assign row_in_top = (pixel_row <= 6'd3);
    assign row_in_bottom = (6'd28 <= pixel_row) & (pixel_row <= 6'd31);
    assign col_in_left = (pixel_col <= 6'd3);
    assign col_in_right = (6'd28 <= pixel_col) & (pixel_col <= 6'd31);
    // most snake tiles have the middle 48x48 pixels filled with snake (except
    // head cuz of the eyes)
    logic center_square;
    assign center_square = row_in_center & col_in_center;

    logic top_seg, bottom_seg, left_seg, right_seg;
    assign top_seg = (row_in_top & col_in_center);
    assign bottom_seg = (row_in_bottom & col_in_center);
    assign left_seg = (col_in_left & row_in_center);
    assign right_seg = (col_in_right & row_in_center);

    logic top_eye_lane, bottom_eye_lane, left_eye_lane, right_eye_lane;
    assign top_eye_lane = (pixel_row >= 6'd8) & (pixel_row <= 6'd11);
    assign bottom_eye_lane = (pixel_row >= 6'd20) & (pixel_row <= 6'd23);
    assign left_eye_lane = (pixel_col >= 6'd8) & (pixel_col <= 6'd11);
    assign right_eye_lane = (pixel_col >= 6'd20) & (pixel_col <= 6'd23);

    logic top_left_eye, top_right_eye, bottom_left_eye, bottom_right_eye;
    assign top_left_eye = top_eye_lane & left_eye_lane;
    assign top_right_eye = top_eye_lane & right_eye_lane;
    assign bottom_left_eye = bottom_eye_lane & left_eye_lane;
    assign bottom_right_eye = bottom_eye_lane & right_eye_lane;

    logic up_head_eyes, left_head_eyes, right_head_eyes, down_head_eyes;
    assign up_head_eyes = (bottom_left_eye | bottom_right_eye);
    assign left_head_eyes = (top_right_eye | bottom_right_eye);
    assign right_head_eyes = (top_left_eye | bottom_left_eye);
    assign down_head_eyes = (top_left_eye | top_right_eye);


    assign RGB_UP_RIGHT   = center_square | top_seg | right_seg;
    assign RGB_UP_LEFT    = center_square | top_seg | left_seg;
    assign RGB_DOWN_RIGHT = center_square | bottom_seg | right_seg;
    assign RGB_DOWN_LEFT  = center_square | bottom_seg | left_seg;

    assign RGB_UP_TAIL    = center_square | top_seg;
    assign RGB_LEFT_TAIL  = center_square | left_seg;
    assign RGB_RIGHT_TAIL = center_square | right_seg;
    assign RGB_DOWN_TAIL  = center_square | bottom_seg;

    assign RGB_UP_HEAD    = top_seg | (center_square & ~up_head_eyes);
    assign RGB_LEFT_HEAD  = left_seg | (center_square & ~left_head_eyes);
    assign RGB_RIGHT_HEAD = right_seg | (center_square & ~right_head_eyes);
    assign RGB_DOWN_HEAD  = bottom_seg | (center_square & ~down_head_eyes);

    assign RGB_UP_DOWN    = center_square | top_seg | bottom_seg;
    assign RGB_LEFT_RIGHT = center_square | left_seg | right_seg;

endmodule : Snake_Tiles