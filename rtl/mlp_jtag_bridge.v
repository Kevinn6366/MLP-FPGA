`timescale 1ns/1ps
// Convert a JTAG-controlled toggle into one request; retain completion for host polling.
module mlp_jtag_bridge (
    input wire clk,
    input wire reset,
    input wire [31:0] x_packed,
    input wire request_toggle,
    output wire busy,
    output reg done_sticky,
    output wire [63:0] y_packed,
    output reg [31:0] completed_count
);
    reg seen_request;
    wire start = !reset && !busy && (request_toggle != seen_request);
    wire done;
    mlp4 core(.clk(clk), .reset(reset), .start(start), .x_packed(x_packed),
              .busy(busy), .done(done), .y_packed(y_packed));
    always @(posedge clk) begin
        if (reset) begin
            seen_request <= request_toggle;
            done_sticky <= 0;
            completed_count <= 0;
        end else begin
            // Busy requests are consumed and ignored, never queued.
            seen_request <= request_toggle;
            if (start) done_sticky <= 0;
            if (done) begin
                done_sticky <= 1;
                completed_count <= completed_count + 1'b1;
            end
        end
    end
endmodule
