// V2.8.7 MG996 positional servo: continuous, bounded back-and-forth cleaning.
// PWM frame stays at 50 Hz; POSITION is controlled by pulse HIGH width,
// not by varying PWM frequency. Default sweep: 1200us .. 1800us.
// All multiplications and divisions below are CONSTANT expressions at elaboration.
// Never power the motor from FPGA GPIO; use external 5~6V supply and common GND.
module pv_servo_pwm #(
    parameter integer CLK_HZ = 74250000,
    parameter integer PWM_HZ = 50,
    parameter integer PARK_PULSE_US = 1500,
    parameter integer SWEEP_MIN_PULSE_US = 1200,
    parameter integer SWEEP_MAX_PULSE_US = 1800,
    parameter integer SWEEP_STEP_US = 20
)(
    input wire clk,
    input wire rst_n,
    input wire alarm_request,
    output wire pwm_out
);
    localparam integer PERIOD_TICKS = CLK_HZ / PWM_HZ;
    localparam integer PARK_TICKS = (64'd1*CLK_HZ*PARK_PULSE_US)/1000000;
    localparam integer MIN_TICKS = (64'd1*CLK_HZ*SWEEP_MIN_PULSE_US)/1000000;
    localparam integer MAX_TICKS = (64'd1*CLK_HZ*SWEEP_MAX_PULSE_US)/1000000;
    localparam integer STEP_TICKS_RAW = (64'd1*CLK_HZ*SWEEP_STEP_US)/1000000;
    localparam integer STEP_TICKS = STEP_TICKS_RAW < 1 ? 1 : STEP_TICKS_RAW;
    localparam integer CW = (PERIOD_TICKS < 3) ? 2 : $clog2(PERIOD_TICKS);

    reg [CW-1:0] period_counter;
    reg [CW-1:0] high_ticks;
    reg sweep_increasing;

    // Both pulse width and the sweep direction change ONLY at the period
    // boundary. All 20ms pulses are complete even if CCL toggles mid-frame.
    // A clean result or CAM ERR deasserts alarm_request. The actuator slews
    // back to PARK rather than jumping between mechanical endpoints.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            period_counter  <= 0;
            high_ticks      <= PARK_TICKS;
            sweep_increasing <= 1'b1;
        end else if (period_counter == PERIOD_TICKS-1) begin
            period_counter <= 0;
            if (alarm_request) begin
                if (sweep_increasing) begin
                    if (high_ticks >= MAX_TICKS-STEP_TICKS) begin
                        high_ticks <= MAX_TICKS;
                        sweep_increasing <= 1'b0;
                    end else high_ticks <= high_ticks + STEP_TICKS;
                end else begin
                    if (high_ticks <= MIN_TICKS+STEP_TICKS) begin
                        high_ticks <= MIN_TICKS;
                        sweep_increasing <= 1'b1;
                    end else high_ticks <= high_ticks - STEP_TICKS;
                end
            end else begin
                // Soft park; no abrupt position change when stain disappears.
                if (high_ticks > PARK_TICKS) begin
                    if (high_ticks <= PARK_TICKS+STEP_TICKS)
                        high_ticks <= PARK_TICKS;
                    else high_ticks <= high_ticks - STEP_TICKS;
                end else if (high_ticks < PARK_TICKS) begin
                    if (high_ticks+STEP_TICKS >= PARK_TICKS)
                        high_ticks <= PARK_TICKS;
                    else high_ticks <= high_ticks + STEP_TICKS;
                end else sweep_increasing <= 1'b1;
            end
        end else period_counter <= period_counter + 1'b1;
    end
    assign pwm_out = rst_n && (period_counter < high_ticks);
endmodule
