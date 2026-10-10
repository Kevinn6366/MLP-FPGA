`timescale 1ns/1ps
// Single user-supplied tensor. All arithmetic is performed by the actual RTL.
module tb_mlp_console;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, start=0;
    reg [31:0] x_packed=0;
    reg [31:0] requested_x;
    wire busy, done;
    wire [63:0] y_packed;
    reg [63:0] result_y;
    integer cycles;
    mlp4 dut(.*);

    task automatic tick;
        @(posedge clk); #1;
    endtask

    initial begin
        if (!$value$plusargs("X=%h", requested_x))
            $fatal(1,"Missing X=<8 hex digits> simulation argument");
        if ((^requested_x) === 1'bx)
            $fatal(1,"Input contains unknown bits");
        tick();
        if (busy!==0 || done!==0 || y_packed!==0)
            $fatal(1,"Reset failed");
        @(negedge clk); reset=0;
        @(negedge clk); x_packed=requested_x; start=1;
        tick();
        if (busy!==1 || done!==0)
            $fatal(1,"Request was not accepted");
        @(negedge clk); start=0;
        cycles=0;
        while (done!==1 && cycles<230) begin
            tick();
            cycles=cycles+1;
            if (done!==1 && busy!==1)
                $fatal(1,"Unexpected idle state before completion");
        end
        if (done!==1 || busy!==0 || cycles!=229)
            $fatal(1,"Unexpected completion or latency: %0d",cycles);
        if ((^y_packed) === 1'bx)
            $fatal(1,"Output contains unknown bits");
        result_y=y_packed;
        tick();
        if (done!==0 || busy!==0 || y_packed!==result_y)
            $fatal(1,"Completion pulse or held output invalid");
        $display("RESULT input=[%0d,%0d,%0d,%0d] output=[%0d,%0d] cycles=%0d",
                 $signed(requested_x[7:0]),$signed(requested_x[15:8]),
                 $signed(requested_x[23:16]),$signed(requested_x[31:24]),
                 $signed(result_y[31:0]),$signed(result_y[63:32]),cycles);
        $finish;
    end
    initial begin
        #10000;
        $fatal(1,"Console simulation timed out");
    end
endmodule
