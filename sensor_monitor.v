// =============================================================================
// File        : sensor_monitor.v
// Description : Per-sensor monitoring block. Samples an 8-bit sensor reading
//               whenever `data_valid` is asserted and classifies it against
//               two programmable thresholds into NORMAL / WARNING / CRITICAL.
//               Raises `event_flag` whenever the reading is NOT normal, which
//               is what the top-level priority arbiter watches.
//
//               level encoding:
//                 2'b00 = NORMAL
//                 2'b01 = WARNING
//                 2'b10 = CRITICAL
// =============================================================================

module sensor_monitor #(
    parameter WARN_THRESH = 8'd150,
    parameter CRIT_THRESH = 8'd200
)(
    input        clk,
    input        rst_n,

    input        data_valid,
    input  [7:0] data_in,

    output reg [7:0] last_value,
    output reg [1:0] level,        // classification of last_value
    output reg       event_flag    // asserted whenever level != NORMAL
);

    localparam NORMAL   = 2'b00;
    localparam WARNING  = 2'b01;
    localparam CRITICAL = 2'b10;

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            last_value <= 8'd0;
            level      <= NORMAL;
            event_flag <= 1'b0;
        end else if (data_valid) begin
            last_value <= data_in;

            if (data_in >= CRIT_THRESH) begin
                level      <= CRITICAL;
                event_flag <= 1'b1;
            end else if (data_in >= WARN_THRESH) begin
                level      <= WARNING;
                event_flag <= 1'b1;
            end else begin
                level      <= NORMAL;
                event_flag <= 1'b0;
            end
        end
    end

endmodule
