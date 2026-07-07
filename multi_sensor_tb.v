`timescale 1ns/1ps
// =============================================================================
// File        : multi_sensor_tb.v
// Description : Self-checking testbench for the multi-sensor processing
//               system. Validates:
//                 1. Reset state (busy=0, report_valid=0)
//                 2. Correct threshold-based classification (NORMAL /
//                    WARNING / CRITICAL) at and around the boundary values
//                 3. Fixed-priority arbitration across simultaneous events
//                    from multiple sensors
//                 4. Timing-correct FSM behavior: busy/report_valid assert
//                    and deassert on the expected cycles relative to the
//                    report_ack handshake
// =============================================================================

module multi_sensor_tb;

    localparam NORMAL   = 2'd0;
    localparam WARNING  = 2'd1;
    localparam CRITICAL = 2'd2;

    reg clk, rst_n;
    reg        s0_valid, s1_valid, s2_valid, s3_valid;
    reg  [7:0] s0_data,  s1_data,  s2_data,  s3_data;
    reg        report_ack;

    wire       busy, report_valid;
    wire [1:0] report_sensor_id, report_level;
    wire [7:0] report_value;

    integer error_count;

    sensor_fsm_top dut (
        .clk(clk), .rst_n(rst_n),
        .s0_valid(s0_valid), .s0_data(s0_data),
        .s1_valid(s1_valid), .s1_data(s1_data),
        .s2_valid(s2_valid), .s2_data(s2_data),
        .s3_valid(s3_valid), .s3_data(s3_data),
        .report_ack(report_ack),
        .busy(busy),
        .report_valid(report_valid),
        .report_sensor_id(report_sensor_id),
        .report_level(report_level),
        .report_value(report_value)
    );

    // ------------------------------------------------------------------
    // Clock
    // ------------------------------------------------------------------
    initial clk = 0;
    always #5 clk = ~clk;

    // ------------------------------------------------------------------
    // Stimulus helpers
    // ------------------------------------------------------------------
    task automatic clear_inputs;
        begin
            s0_valid = 0; s1_valid = 0; s2_valid = 0; s3_valid = 0;
            s0_data = 0;  s1_data = 0;  s2_data = 0;  s3_data = 0;
        end
    endtask

    // Drive a single sensor's reading for exactly one clock edge.
    task automatic send_sensor(input [1:0] id, input [7:0] value);
        begin
            @(negedge clk);
            case (id)
                2'd0: begin s0_valid = 1; s0_data = value; end
                2'd1: begin s1_valid = 1; s1_data = value; end
                2'd2: begin s2_valid = 1; s2_data = value; end
                2'd3: begin s3_valid = 1; s3_data = value; end
            endcase
            @(negedge clk);
            clear_inputs;
        end
    endtask

    // Drive two sensors' readings on the same clock edge (simultaneous event).
    task automatic send_two(input [1:0] id_a, input [7:0] val_a,
                            input [1:0] id_b, input [7:0] val_b);
        begin
            @(negedge clk);
            case (id_a)
                2'd0: begin s0_valid = 1; s0_data = val_a; end
                2'd1: begin s1_valid = 1; s1_data = val_a; end
                2'd2: begin s2_valid = 1; s2_data = val_a; end
                2'd3: begin s3_valid = 1; s3_data = val_a; end
            endcase
            case (id_b)
                2'd0: begin s0_valid = 1; s0_data = val_b; end
                2'd1: begin s1_valid = 1; s1_data = val_b; end
                2'd2: begin s2_valid = 1; s2_data = val_b; end
                2'd3: begin s3_valid = 1; s3_data = val_b; end
            endcase
            @(negedge clk);
            clear_inputs;
        end
    endtask

    task automatic check_eq(input [63:0] got, input [63:0] exp, input [255:0] msg);
        begin
            if (got !== exp) begin
                error_count = error_count + 1;
                $display("[%0t] ERROR: %0s  expected=%0d got=%0d", $time, msg, exp, got);
            end
        end
    endtask

    // Wait (with timeout) for report_valid to assert, then check its fields.
    task automatic expect_report(input [1:0] exp_id, input [1:0] exp_level, input [7:0] exp_value);
        integer guard;
        begin
            guard = 0;
            while (!report_valid && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard == 20) begin
                error_count = error_count + 1;
                $display("[%0t] ERROR: timed out waiting for report_valid", $time);
            end else begin
                check_eq(report_sensor_id, exp_id,    "report_sensor_id mismatch");
                check_eq(report_level,     exp_level, "report_level mismatch");
                check_eq(report_value,     exp_value, "report_value mismatch");
                check_eq(busy,             1'b1,      "busy should be asserted during report");
            end
        end
    endtask

    // Acknowledge the current report and confirm the FSM returns to idle.
    task automatic ack_report;
        integer guard;
        begin
            @(negedge clk);
            report_ack = 1;
            @(negedge clk);
            report_ack = 0;

            guard = 0;
            while (report_valid && guard < 20) begin
                @(posedge clk);
                guard = guard + 1;
            end
            if (guard == 20) begin
                error_count = error_count + 1;
                $display("[%0t] ERROR: report_valid never deasserted after ack", $time);
            end
            @(posedge clk);
            check_eq(busy, 1'b0, "busy should deassert after ack + return to idle");
        end
    endtask

    // ------------------------------------------------------------------
    // Main test sequence
    // ------------------------------------------------------------------
    initial begin
        error_count = 0;
        rst_n = 0;
        report_ack = 0;
        clear_inputs;

        repeat (3) @(posedge clk);
        rst_n = 1;

        // ---------------- Phase 0: reset sanity ----------------
        @(posedge clk);
        check_eq(busy,         1'b0, "busy should be 0 after reset");
        check_eq(report_valid, 1'b0, "report_valid should be 0 after reset");
        $display("[%0t] Phase 0 (reset) complete.", $time);

        // ---------------- Phase 1: basic classification + report ----------------
        // Sensor 1 goes CRITICAL (>= 200)
        send_sensor(2'd1, 8'd220);
        expect_report(2'd1, CRITICAL, 8'd220);
        // Clear sensor1's event *before* acking, so the FSM doesn't
        // immediately re-capture the still-pending event on return to IDLE.
        send_sensor(2'd1, 8'd10);
        ack_report;

        // Sensor 3 goes WARNING (>=150 and <200)
        send_sensor(2'd3, 8'd170);
        expect_report(2'd3, WARNING, 8'd170);
        send_sensor(2'd3, 8'd10);
        ack_report;

        $display("[%0t] Phase 1 (basic classification/report) complete.", $time);

        // ---------------- Phase 2: threshold boundary checks (sensor 3, isolated) ----------------
        send_sensor(2'd3, 8'd149);   // just below WARNING -> NORMAL, no report expected
        if (report_valid) begin
            error_count = error_count + 1;
            $display("[%0t] ERROR: unexpected report for NORMAL value 149", $time);
        end

        send_sensor(2'd3, 8'd150);   // exactly at WARNING threshold
        expect_report(2'd3, WARNING, 8'd150);
        send_sensor(2'd3, 8'd10);
        ack_report;

        send_sensor(2'd3, 8'd199);   // just below CRITICAL -> still WARNING
        expect_report(2'd3, WARNING, 8'd199);
        send_sensor(2'd3, 8'd10);
        ack_report;

        send_sensor(2'd3, 8'd200);   // exactly at CRITICAL threshold
        expect_report(2'd3, CRITICAL, 8'd200);
        send_sensor(2'd3, 8'd10);
        ack_report;

        $display("[%0t] Phase 2 (threshold boundaries) complete.", $time);

        // ---------------- Phase 3: fixed-priority arbitration ----------------
        // Sensor 0 (WARNING) and Sensor 2 (CRITICAL) trigger on the same cycle.
        // Sensor 0 has higher fixed priority and must be reported first,
        // regardless of its lower severity level.
        send_two(2'd0, 8'd160, 2'd2, 8'd210);
        expect_report(2'd0, WARNING, 8'd160);

        // Clear sensor0's event *before* acking; sensor2's event is still
        // pending and must now win arbitration on the next round.
        send_sensor(2'd0, 8'd5);
        ack_report;

        expect_report(2'd2, CRITICAL, 8'd210);
        send_sensor(2'd2, 8'd5);
        ack_report;

        $display("[%0t] Phase 3 (priority arbitration) complete.", $time);

        // ---------------- Phase 4: all four sensors simultaneously ----------------
        // All go CRITICAL on the same edge; expect strict priority order
        // 0 -> 1 -> 2 -> 3, clearing each one's event before acking so the
        // next-highest-priority sensor wins arbitration on the next round.
        @(negedge clk);
        s0_valid = 1; s0_data = 8'd255;
        s1_valid = 1; s1_data = 8'd255;
        s2_valid = 1; s2_data = 8'd255;
        s3_valid = 1; s3_data = 8'd255;
        @(negedge clk);
        clear_inputs;

        expect_report(2'd0, CRITICAL, 8'd255);
        send_sensor(2'd0, 8'd5);
        ack_report;

        expect_report(2'd1, CRITICAL, 8'd255);
        send_sensor(2'd1, 8'd5);
        ack_report;

        expect_report(2'd2, CRITICAL, 8'd255);
        send_sensor(2'd2, 8'd5);
        ack_report;

        expect_report(2'd3, CRITICAL, 8'd255);
        send_sensor(2'd3, 8'd5);
        ack_report;

        $display("[%0t] Phase 4 (four-way simultaneous priority) complete.", $time);

        // ---------------- Summary ----------------
        $display("=====================================================");
        if (error_count == 0)
            $display("TEST PASSED: all checks passed, 0 errors.");
        else
            $display("TEST FAILED: %0d error(s) detected.", error_count);
        $display("=====================================================");

        $finish;
    end

    initial begin
        #50000;
        $display("ERROR: TESTBENCH TIMEOUT");
        $finish;
    end

endmodule
