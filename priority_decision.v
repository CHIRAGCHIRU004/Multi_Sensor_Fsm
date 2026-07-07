// =============================================================================
// File        : priority_decision.v
// Description : Fixed-priority combinational arbiter across four sensor
//               monitors. Sensor 0 has the highest priority, sensor 3 the
//               lowest. Selects the highest-priority sensor currently
//               reporting a non-NORMAL event and forwards its id/level/value
//               to the top-level FSM for reporting.
// =============================================================================

module priority_decision (
    input        ev0,  input        ev1,  input        ev2,  input        ev3,
    input  [1:0] lvl0, input  [1:0] lvl1, input  [1:0] lvl2, input  [1:0] lvl3,
    input  [7:0] val0, input  [7:0] val1, input  [7:0] val2, input  [7:0] val3,

    output reg       have_event,
    output reg [1:0] sel_id,      // which sensor (0-3) was selected
    output reg [1:0] sel_level,
    output reg [7:0] sel_value
);

    always @* begin
        if (ev0) begin
            have_event = 1'b1; sel_id = 2'd0; sel_level = lvl0; sel_value = val0;
        end else if (ev1) begin
            have_event = 1'b1; sel_id = 2'd1; sel_level = lvl1; sel_value = val1;
        end else if (ev2) begin
            have_event = 1'b1; sel_id = 2'd2; sel_level = lvl2; sel_value = val2;
        end else if (ev3) begin
            have_event = 1'b1; sel_id = 2'd3; sel_level = lvl3; sel_value = val3;
        end else begin
            have_event = 1'b0; sel_id = 2'd0; sel_level = 2'd0; sel_value = 8'd0;
        end
    end

endmodule
