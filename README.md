# RTL Design of Multi-Sensor Processing System

An FSM-based Verilog HDL system that monitors multiple independent sensor
channels, classifies each reading's severity, and arbitrates among
simultaneous events using fixed-priority resolution — modeling a
priority-driven sensor event classification pipeline.

## Highlights

- **FSM-based priority-driven classification**: a `IDLE -> CAPTURE ->
  WAIT_ACK` control FSM captures the arbiter's winning event and holds it
  stable for a downstream consumer via a valid/ack handshake.
- **Modular RTL blocks**: each sensor has its own `sensor_monitor` instance
  (independent threshold classification), decoupled from the shared
  `priority_decision` arbitration logic and the top-level control FSM.
- **Fixed-priority arbitration**: sensor 0 is highest priority, sensor 3
  lowest — the arbiter always reports the highest-priority *active* event
  first, regardless of its severity relative to other pending events.
- **Simulation testbench** validating timing-correct functionality:
  threshold boundaries, single-event reporting, multi-sensor priority
  resolution, and FSM busy/valid timing relative to the ack handshake.
- **Optimized state encoding**: a 3-state FSM (`IDLE`, `CAPTURE`,
  `WAIT_ACK`) keeps control logic minimal while still supporting a clean
  handshake with an external consumer.

## Repository Structure

```
multi-sensor-fsm/
├── rtl/
│   ├── sensor_fsm_top.v      # Top-level: instantiates monitors + arbiter + FSM
│   ├── sensor_monitor.v      # Per-sensor threshold classification block
│   └── priority_decision.v   # Fixed-priority combinational arbiter
├── tb/
│   └── multi_sensor_tb.v     # Self-checking testbench
└── README.md
```

## Classification Thresholds

Each `sensor_monitor` classifies its 8-bit reading into one of three levels
(thresholds are parameterizable per instance):

| Level      | Condition              | Encoding |
|------------|-------------------------|----------|
| NORMAL     | `value < 150`           | `2'b00`  |
| WARNING    | `150 <= value < 200`    | `2'b01`  |
| CRITICAL   | `value >= 200`          | `2'b10`  |

## Top-Level Interface

```verilog
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
```

| Signal              | Direction | Description                                   |
|---------------------|-----------|------------------------------------------------|
| `sN_valid`/`sN_data`| in        | Per-sensor (N=0..3) new-reading strobe + value |
| `report_ack`        | in        | Consumer acknowledges the current report       |
| `busy`              | out       | High whenever the FSM is capturing/reporting    |
| `report_valid`      | out       | High while a classified event is ready to read  |
| `report_sensor_id`  | out       | Which sensor (0-3) the current report is from   |
| `report_level`      | out       | NORMAL/WARNING/CRITICAL of the current report   |
| `report_value`      | out       | Raw sensor value of the current report          |

## FSM Behavior

```
        have_event
 IDLE ───────────────► CAPTURE ───────────────► WAIT_ACK
   ▲   (arbiter picks     │ (latch sel_id/level/    │
   │   highest-priority   │  value, assert          │
   │   active event)      │  report_valid)          │
   └───────────────────────────────────────────────┘
                report_ack (report_valid deasserts)
```

If a higher-priority sensor's event is still pending when the FSM returns
to `IDLE`, it will win arbitration again immediately — by design, this
guarantees the highest-priority outstanding condition is always reported
next, but it also means a persistently critical high-priority sensor can
starve lower-priority reports until its condition clears (a real system
would typically pair this with a fairness/round-robin extension if
starvation is undesirable — noted here for design-review completeness).

## Running the Testbench (Icarus Verilog)

```bash
iverilog -g2005 -o sensor_sim tb/multi_sensor_tb.v rtl/*.v
vvp sensor_sim
```

Expected output ends with:

```
TEST PASSED: all checks passed, 0 errors.
```

The testbench covers:
1. **Reset behavior** — `busy`/`report_valid` low out of reset.
2. **Basic classification + report** — single-sensor WARNING/CRITICAL
   events reported with correct id/level/value.
3. **Threshold boundaries** — values at 149/150/199/200 verified against
   the exact NORMAL/WARNING/CRITICAL cutoffs.
4. **Priority arbitration** — two, then four, simultaneous sensor events
   verified to report in strict fixed-priority order (0→1→2→3), with each
   winning sensor's event cleared before acknowledging so the next
   highest-priority pending event is correctly picked up.

## Running in Vivado

1. Create a new RTL project and add all files under `rtl/` as design sources.
2. Add `tb/multi_sensor_tb.v` as a simulation-only source.
3. Set `multi_sensor_tb` as the top module for the Simulation fileset.
4. Run Behavioral Simulation; the transcript reports the same
   `TEST PASSED` / `TEST FAILED` summary.
