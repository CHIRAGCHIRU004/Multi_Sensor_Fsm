// =============================================================================
// File        : sensor_fsm_top.v
// Description : Top-level RTL for the multi-sensor processing system.
//               Instantiates four independent sensor_monitor blocks, feeds
//               their event/level/value outputs into a fixed-priority
//               arbiter, and drives a simple capture/report FSM that
//               latches the winning event and holds it stable on a
//               valid/ack handshake until the consumer acknowledges it.
//
//               FSM states:
//                 IDLE     - waiting for any sensor event
//                 CAPTURE  - latch the arbiter's winning event this cycle
//                 WAIT_ACK - report_valid held high until report_ack seen
// =============================================================================

module sensor_fsm_top (
    input        clk,
    input        rst_n,

    // Sensor 0..3 raw inputs
    input        s0_valid, input [7:0] s0_data,
    input        s1_valid, input [7:0] s1_data,
    input        s2_valid, input [7:0] s2_data,
    input        s3_valid, input [7:0] s3_data,

    // Consumer handshake
    input        report_ack,

    // Reported classification
    output reg       busy,
    output reg       report_valid,
    output reg [1:0] report_sensor_id,
    output reg [1:0] report_level,
    output reg [7:0] report_value
);

    // ------------------------------------------------------------------
    // Per-sensor monitoring blocks
    // ------------------------------------------------------------------
    wire       ev0, ev1, ev2, ev3;
    wire [1:0] lvl0, lvl1, lvl2, lvl3;
    wire [7:0] val0, val1, val2, val3;

    sensor_monitor u_sensor0 (.clk(clk), .rst_n(rst_n), .data_valid(s0_valid), .data_in(s0_data), .last_value(val0), .level(lvl0), .event_flag(ev0));
    sensor_monitor u_sensor1 (.clk(clk), .rst_n(rst_n), .data_valid(s1_valid), .data_in(s1_data), .last_value(val1), .level(lvl1), .event_flag(ev1));
    sensor_monitor u_sensor2 (.clk(clk), .rst_n(rst_n), .data_valid(s2_valid), .data_in(s2_data), .last_value(val2), .level(lvl2), .event_flag(ev2));
    sensor_monitor u_sensor3 (.clk(clk), .rst_n(rst_n), .data_valid(s3_valid), .data_in(s3_data), .last_value(val3), .level(lvl3), .event_flag(ev3));

    // ------------------------------------------------------------------
    // Priority arbiter
    // ------------------------------------------------------------------
    wire       have_event;
    wire [1:0] sel_id, sel_level;
    wire [7:0] sel_value;

    priority_decision u_priority (
        .ev0(ev0), .ev1(ev1), .ev2(ev2), .ev3(ev3),
        .lvl0(lvl0), .lvl1(lvl1), .lvl2(lvl2), .lvl3(lvl3),
        .val0(val0), .val1(val1), .val2(val2), .val3(val3),
        .have_event(have_event),
        .sel_id(sel_id),
        .sel_level(sel_level),
        .sel_value(sel_value)
    );

    // ------------------------------------------------------------------
    // Capture / report FSM
    // ------------------------------------------------------------------
    localparam S_IDLE     = 2'd0;
    localparam S_CAPTURE  = 2'd1;
    localparam S_WAIT_ACK = 2'd2;

    reg [1:0] state, next_state;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n)
            state <= S_IDLE;
        else
            state <= next_state;
    end

    always @* begin
        next_state = state;
        case (state)
            S_IDLE:     next_state = have_event ? S_CAPTURE : S_IDLE;
            S_CAPTURE:  next_state = S_WAIT_ACK;
            S_WAIT_ACK: next_state = report_ack ? S_IDLE : S_WAIT_ACK;
            default:    next_state = S_IDLE;
        endcase
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            busy             <= 1'b0;
            report_valid     <= 1'b0;
            report_sensor_id <= 2'd0;
            report_level     <= 2'd0;
            report_value     <= 8'd0;
        end else begin
            busy <= (next_state != S_IDLE);

            case (state)
                S_CAPTURE: begin
                    // Latch the arbiter's winning event this cycle
                    report_sensor_id <= sel_id;
                    report_level     <= sel_level;
                    report_value     <= sel_value;
                    report_valid     <= 1'b1;
                end
                S_WAIT_ACK: begin
                    if (report_ack)
                        report_valid <= 1'b0;
                end
                default: begin
                    report_valid <= 1'b0;
                end
            endcase
        end
    end

endmodule
