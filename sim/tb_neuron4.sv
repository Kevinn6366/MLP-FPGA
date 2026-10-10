`timescale 1ns/1ps
module tb_neuron4;
    reg clk=0;
    always #5 clk=~clk; // 100 MHz simulation clock; not a board timing claim.
    reg reset=1, start=0;
    reg [31:0] x_packed=0, w_packed=0;
    reg signed [15:0] bias=0;
    wire busy,done;
    wire signed [17:0] y;
    neuron4 dut(.*);
    integer case_count=0;
    integer result_file;

    task automatic tick;
        @(posedge clk); #1; // Observe after nonblocking register assignments.
    endtask
    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL case=%0d: %s",case_count,message);
            $fatal(1,"Self-check failed");
        end
    endtask

    task automatic run_case(
        input reg [31:0] xv, wv,
        input reg [15:0] bv,
        input integer a0,a1,a2,a3,a4,expected
    );
        integer j;
        integer expected_acc[0:4];
        reg signed [17:0] old_y;
        begin
            expected_acc[0]=a0; expected_acc[1]=a1; expected_acc[2]=a2;
            expected_acc[3]=a3; expected_acc[4]=a4;
            @(negedge clk);
            old_y=y;
            x_packed=xv; w_packed=wv; bias=bv; start=1;
            tick();
            check(busy===1 && done===0,"request accepted");
            check($signed(dut.acc)===a0,"initial bias sign extension");
            for(j=1;j<=4;j=j+1) begin
                @(negedge clk);
                // Mutate inputs and pulse start while busy: captured operands must win.
                start=(j==2);
                x_packed=32'hdeadbeef; w_packed=32'h76543210; bias=-123;
                tick();
                check(busy===1 && done===0,"busy asserted; no early done");
                check(y===old_y,"output held until completion");
                check($signed(dut.acc)===expected_acc[j],$sformatf("MAC step %0d",j));
            end
            @(negedge clk); start=0;
            tick();
            check(done===1 && busy===0,"done exactly five clocks after acceptance");
            check($signed(y)===expected,"ReLU output matches Python oracle");
            $display("PASS case %0d: acc=%0d,%0d,%0d,%0d,%0d y=%0d",
                case_count,a0,a1,a2,a3,a4,$signed(y));
            tick();
            check(done===0 && busy===0,"done is a one-cycle pulse; busy start was ignored");
            check($signed(y)===expected,"output remains stable in idle");
            case_count=case_count+1;
        end
    endtask

    initial begin
        tick();
        check(busy===0 && done===0 && y===0,"reset initializes outputs");
        @(negedge clk); reset=0;
        `include "vectors.vh"
        // Abort a transaction with synchronous reset and prove no delayed completion.
        @(negedge clk); start=1; x_packed=32'h01010101; w_packed=32'h01010101; bias=0;
        tick();
        @(negedge clk); start=0;
        tick();
        @(negedge clk); reset=1; start=1;
        tick();
        check(busy===0 && done===0 && y===0 && dut.acc===0,"reset overrides active request");
        @(negedge clk); reset=0; start=0;
        repeat(7) begin
            tick();
            check(busy===0 && done===0 && y===0,"reset cancels in-flight work");
        end
        run_case(32'h04030201,32'h0001ff02,16'h0001,1,3,1,4,4,4);
        $display("ALL_PASS: %0d numerical cases plus reset/handshake checks",case_count);
        result_file=$fopen("simulation_result.txt","w");
        if(result_file==0) $fatal(1,"Cannot write result marker");
        $fdisplay(result_file,"ALL_PASS: %0d numerical cases plus reset/handshake checks",case_count);
        $fclose(result_file);
        $finish;
    end
    initial begin
        #100000;
        $fatal(1,"Watchdog timeout");
    end
endmodule
