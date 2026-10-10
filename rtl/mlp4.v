`timescale 1ns/1ps
// Fixed integer MLP: [1,4] -> [1,8] -> [1,8] -> [1,8] -> [1,2].
// Lane 0 is the least significant lane. Hidden layers use ReLU.
// Synchronous reset; request accepted only in IDLE; done pulses for one cycle.
module mlp4 (
    input wire clk,
    input wire reset,
    input wire start,
    input wire [31:0] x_packed,
    output reg busy,
    output reg done,
    output reg [63:0] y_packed
);
    localparam IDLE=3'd0, INIT=3'd1, MAC=3'd2,
               STORE=3'd3, FINISH=3'd4;
    reg [2:0] state;
    reg [1:0] layer;
    reg [2:0] neuron;
    reg [2:0] input_index;
    // Even layers read A/write B; odd layers read B/write A.
    reg signed [31:0] bank_a [0:7];
    reg signed [31:0] bank_b [0:7];
    reg signed [39:0] acc;
    wire [3:0] input_count = (layer == 0) ? 4'd4 : 4'd8;
    wire [3:0] output_count = (layer == 3) ? 4'd2 : 4'd8;
    wire [7:0] weight_base = (layer == 0) ? 8'd0 :
                             (layer == 1) ? 8'd32 :
                             (layer == 2) ? 8'd96 : 8'd160;
    wire [4:0] bias_base = (layer == 0) ? 5'd0 :
                           (layer == 1) ? 5'd8 :
                           (layer == 2) ? 5'd16 : 5'd24;
    // Row-major weight layout: W[layer][output_neuron][input_index].
    wire [7:0] row_offset = (layer == 0) ? {3'b0, neuron, 2'b0}
                                                        : {2'b0, neuron, 3'b0};
    wire [7:0] weight_address = weight_base + row_offset + input_index;
    wire [4:0] bias_address = bias_base + neuron;
    `include "mlp4_weights.vh"
    wire signed [7:0] weight_value = weight_rom(weight_address);
    wire signed [15:0] bias_value = bias_rom(bias_address);
    wire signed [31:0] operand = layer[0] ? bank_b[input_index] : bank_a[input_index];
    wire signed [39:0] product = operand * weight_value;
    // The generator proves |all intermediates| <= 21,349,064 for legal inputs.
    // Thus taking bits [31:0] here is exact, with no rounding or saturation.
    wire signed [31:0] neuron_value = (layer != 3 && acc[39]) ? 32'sd0 : acc[31:0];
    integer k;

    always @(posedge clk) begin
        if (reset) begin
            state <= IDLE;
            layer <= 0;
            neuron <= 0;
            input_index <= 0;
            acc <= 0;
            busy <= 0;
            done <= 0;
            y_packed <= 0;
            for (k=0; k<8; k=k+1) begin
                bank_a[k] <= 0;
                bank_b[k] <= 0;
            end
        end else begin
            done <= 0;
            case (state)
                IDLE: if (start) begin
                    for (k=0; k<4; k=k+1)
                        bank_a[k] <= {{24{x_packed[k*8+7]}}, x_packed[k*8 +: 8]};
                    layer <= 0;
                    neuron <= 0;
                    input_index <= 0;
                    busy <= 1;
                    state <= INIT;
                end
                INIT: begin
                    acc <= {{24{bias_value[15]}}, bias_value};
                    input_index <= 0;
                    state <= MAC;
                end
                MAC: begin
                    acc <= acc + product;
                    if (input_index == input_count - 1'b1)
                        state <= STORE;
                    else
                        input_index <= input_index + 1'b1;
                end
                STORE: begin
                    if (layer[0]) bank_a[neuron] <= neuron_value;
                    else          bank_b[neuron] <= neuron_value;
                    if (neuron == output_count - 1'b1) begin
                        neuron <= 0;
                        if (layer == 3) state <= FINISH;
                        else begin
                            layer <= layer + 1'b1;
                            state <= INIT;
                        end
                    end else begin
                        neuron <= neuron + 1'b1;
                        state <= INIT;
                    end
                end
                FINISH: begin
                    // Both output elements become visible together.
                    y_packed <= {bank_a[1], bank_a[0]};
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
