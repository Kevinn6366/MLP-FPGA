`timescale 1ns/1ps
module mlp_board_top(input wire sysclk);
    wire clk, locked;
    mlp_clock clocking(.clk_in1(sysclk), .clk_out1(clk), .locked(locked));
    (* ASYNC_REG = "TRUE" *) reg [2:0] reset_pipe = 3'b111;
    always @(posedge clk or negedge locked) begin
        if (!locked) reset_pipe <= 3'b111;
        else reset_pipe <= {reset_pipe[1:0], 1'b0};
    end
    (* KEEP = "TRUE" *) wire [31:0] vio_x;
    (* KEEP = "TRUE" *) wire vio_request;
    (* KEEP = "TRUE" *) wire vio_reset;
    (* KEEP = "TRUE" *) wire [63:0] vio_y;
    (* KEEP = "TRUE" *) wire [31:0] vio_status;
    (* KEEP = "TRUE" *) wire [31:0] vio_count;
    (* KEEP = "TRUE" *) wire [31:0] vio_id = 32'h4d4c5034;
    wire busy, done_sticky;
    wire reset = reset_pipe[2] | vio_reset;
    assign vio_status = {29'd0, locked, done_sticky, busy};
    mlp_jtag_bridge inference(.clk(clk), .reset(reset), .x_packed(vio_x),
        .request_toggle(vio_request), .busy(busy), .done_sticky(done_sticky),
        .y_packed(vio_y), .completed_count(vio_count));
    mlp_vio debug_io(.clk(clk),
        .probe_in0(vio_y), .probe_in1(vio_status),
        .probe_in2(vio_count), .probe_in3(vio_id),
        .probe_out0(vio_x), .probe_out1(vio_request), .probe_out2(vio_reset));
endmodule
