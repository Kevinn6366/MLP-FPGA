`timescale 1ns/1ps
// One neuron: ReLU(bias + sum(x[i] * w[i])), i=0..3.
// Lane 0 occupies bits [7:0]. Inputs are captured only on start && !busy.
// Synchronous active-high reset. done is a one-cycle pulse.
module neuron4 (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [31:0] x_packed,
    input wire [31:0] w_packed,
    input wire signed [15:0] bias,
    output reg busy,
    output reg done,
    output reg signed [17:0] y
);
    localparam IDLE=2'd0, MAC=2'd1, OUTPUT_RESULT=2'd2;
    reg [1:0] state;
    reg [1:0] index;
    reg signed [7:0] xs [0:3];
    reg signed [7:0] ws [0:3];
    reg signed [17:0] acc;
    wire signed [15:0] product = xs[index] * ws[index];
    wire signed [17:0] extended_product = {{2{product[15]}}, product};
    integer k;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            index <= 0;
            acc <= 0;
            y <= 0;
            busy <= 0;
            done <= 0;
            for (k=0; k<4; k=k+1) begin
                xs[k] <= 0;
                ws[k] <= 0;
            end
        end else begin
            done <= 0;
            case (state)
                IDLE: begin
                    if (start) begin
                        for (k=0; k<4; k=k+1) begin
                            xs[k] <= x_packed[k*8 +: 8];
                            ws[k] <= w_packed[k*8 +: 8];
                        end
                        acc <= {{2{bias[15]}}, bias};
                        index <= 0;
                        busy <= 1;
                        state <= MAC;
                    end
                end
                MAC: begin
                    acc <= acc + extended_product;
                    if (index == 3)
                        state <= OUTPUT_RESULT;
                    else
                        index <= index + 1'b1;
                end
                OUTPUT_RESULT: begin
                    y <= acc[17] ? 18'sd0 : acc;
                    busy <= 0;
                    done <= 1;
                    state <= IDLE;
                end
                default: begin
                    state <= IDLE;
                    busy <= 0;
                end
            endcase
        end
    end
endmodule
