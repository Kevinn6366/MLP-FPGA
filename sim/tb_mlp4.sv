`timescale 1ns/1ps
module tb_mlp4;
    reg clk=0;
    always #5 clk=~clk;
    reg reset=1, start=0;
    reg [31:0] x_packed=0;
    wire busy, done;
    wire [63:0] y_packed;
    mlp4 dut(.*);
    integer case_count=0, checked_neurons=0, result_file;
    integer final_negative=0, final_positive=0;
    integer hidden_negative=0, hidden_positive=0;

    task automatic tick;
        @(posedge clk); #1;
    endtask
    task automatic check(input bit condition, input string message);
        if (!condition) begin
            $display("FAIL case=%0d t=%0t: %s",case_count,$time,message);
            $fatal(1,"MLP self-check failed");
        end
    endtask

    task automatic run_case(input reg [31:0] xv,
                            input reg [831:0] expected_acts,
                            input reg [831:0] expected_raw);
        integer cycle, slot, saved_layer, saved_neuron;
        integer store_count;
        reg was_store;
        reg [63:0] old_y;
        reg signed [31:0] expected_value, raw_value;
        begin
            @(negedge clk);
            old_y=y_packed;
            x_packed=xv; start=1;
            tick();
            check(busy===1 && done===0,"accept request");
            check(dut.state===3'd1 && dut.layer===0 && dut.neuron===0,"initial scheduling");
            store_count=0;
            for(cycle=1; cycle<=229; cycle=cycle+1) begin
                @(negedge clk);
                // Captured inputs must remain authoritative; busy start is ignored.
                x_packed=~xv;
                start=(cycle==2 || cycle==48 || cycle==128 || cycle==228);
                was_store=(dut.state===3'd3);
                saved_layer=dut.layer; saved_neuron=dut.neuron;
                if(was_store) begin
                    slot=saved_layer*8+saved_neuron;
                    expected_value=expected_acts[slot*32 +: 32];
                    raw_value=expected_raw[slot*32 +: 32];
                    check($signed(dut.acc)===$signed(raw_value),
                          $sformatf("preactivation layer=%0d neuron=%0d",saved_layer,saved_neuron));
                    if(saved_layer<3) begin
                        if(raw_value<0) hidden_negative=hidden_negative+1;
                        if(raw_value>0) hidden_positive=hidden_positive+1;
                    end else begin
                        if(raw_value<0) final_negative=final_negative+1;
                        if(raw_value>0) final_positive=final_positive+1;
                    end
                end
                tick();
                if(was_store) begin
                    if(saved_layer%2==0)
                        check(dut.bank_b[saved_neuron]===expected_value,
                              $sformatf("bank B layer=%0d neuron=%0d",saved_layer,saved_neuron));
                    else
                        check(dut.bank_a[saved_neuron]===expected_value,
                              $sformatf("bank A layer=%0d neuron=%0d",saved_layer,saved_neuron));
                    store_count=store_count+1;
                    checked_neurons=checked_neurons+1;
                end
                if(cycle<229) begin
                    check(busy===1 && done===0,"busy throughout transaction; no early done");
                    check(y_packed===old_y,"output tensor held until atomic completion");
                end else begin
                    check(busy===0 && done===1,"completion exactly 229 clocks after acceptance");
                    check(y_packed===expected_acts[768 +: 64],"final tensor equals Python");
                end
            end
            check(store_count==26,"all 26 neurons visited exactly once");
            @(negedge clk); start=0;
            tick();
            check(done===0 && busy===0,"one-cycle done; busy requests not queued");
            check(y_packed===expected_acts[768 +: 64],"output tensor stable in idle");
            $display("PASS case %0d x=%h y=[%0d,%0d] cycles=229 neurons=26",case_count,xv,
                     $signed(y_packed[31:0]),$signed(y_packed[63:32]));
            case_count=case_count+1;
        end
    endtask

    task automatic abort_case(input integer elapsed);
        integer j;
        begin
            @(negedge clk); start=1; x_packed=32'h7f807f80;
            tick();
            @(negedge clk); start=0;
            repeat(elapsed) tick();
            check(busy===1,"reset test starts during active calculation");
            @(negedge clk); reset=1; start=1;
            tick();
            check(busy===0 && done===0 && y_packed===0 && dut.acc===0,"reset takes priority");
            for(j=0;j<8;j=j+1)
                check(dut.bank_a[j]===0 && dut.bank_b[j]===0,"reset clears tensor banks");
            @(negedge clk); reset=0; start=0;
            repeat(232) begin
                tick();
                check(busy===0 && done===0 && y_packed===0,"aborted work never completes later");
            end
        end
    endtask

    initial begin
        tick();
        check(busy===0 && done===0 && y_packed===0,"initial reset");
        @(negedge clk); reset=0;
        `include "mlp4_vectors.vh"
        // Cancel in each layer and immediately before FINISH, then prove restart.
        abort_case(3);
        abort_case(60);
        abort_case(140);
        abort_case(215);
        abort_case(228);
        `include "mlp4_vectors.vh"
        check(case_count==186 && checked_neurons==4836,"full regression completed");
        check(hidden_negative>0 && hidden_positive>0,"both ReLU branches exercised");
        check(final_negative>0 && final_positive>0,"signed final layer; no output ReLU");
        $display("COVERAGE neurons=%0d hidden_negative=%0d hidden_positive=%0d final_negative=%0d final_positive=%0d",
                  checked_neurons,hidden_negative,hidden_positive,final_negative,final_positive);
        $display("ALL_PASS: 186 tensors, 4836 neurons, 5 reset aborts, latency 229 cycles");
        result_file=$fopen("mlp4_result.txt","w");
        if(result_file==0) $fatal(1,"Cannot write result marker");
        $fdisplay(result_file,"ALL_PASS: 186 tensors, 4836 neurons, 5 reset aborts, latency 229 cycles");
        $fclose(result_file);
        $finish;
    end
    initial begin
        #1000000;
        $fatal(1,"Watchdog timeout");
    end
endmodule
