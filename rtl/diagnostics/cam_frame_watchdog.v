// V2.8.1: CSI valid-frame watchdog, clocked from the always-running
// 24MHz platform clock, NOT the CSI recovered clock.  No sensor reset or
// I2C reinitialization is performed here.
module cam_frame_watchdog #(
    parameter integer CLOCK_HZ = 24000000,
    parameter integer TIMEOUT_MS = 100
) (
    input wire clk,
    input wire rst_n,
    input wire armed,              // SC520CS initial I2C setup completed
    input wire good_frame_toggle_async, // toggle per FULL 720-line valid frame
    output reg fault,
    output reg [7:0] fault_count
);
    localparam integer LIMIT_RAW = (CLOCK_HZ / 1000) * TIMEOUT_MS;
    localparam integer LIMIT = (LIMIT_RAW < 2) ? 2 : LIMIT_RAW;
    localparam integer W = $clog2(LIMIT);
    (* async_reg = "true" *) reg frame_meta;
    (* async_reg = "true" *) reg frame_sync;
    reg frame_seen;
    reg [W-1:0] elapsed;

    // Synchronize EVENT TOGGLE; works even if the CSI clock stops entirely.
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_meta <= 1'b0;
            frame_sync <= 1'b0;
        end else begin
            frame_meta <= good_frame_toggle_async;
            frame_sync <= frame_meta;
        end
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            frame_seen <= 1'b0;
            elapsed <= {W{1'b0}};
            fault <= 1'b0;
            fault_count <= 8'd0;
        end else if (!armed) begin
            // No false "CAM ERR" during I2C initialization.
            frame_seen <= frame_sync;
            elapsed <= {W{1'b0}};
            fault <= 1'b0;
            // Preserve accumulated fault events unless the FPGA is reset.
        end else if (frame_sync != frame_seen) begin
            frame_seen <= frame_sync;
            elapsed <= {W{1'b0}};
            // Incoming full frames may clear the flag, but no sensor re-init
            // is requested or attempted by this version.
            fault <= 1'b0;
        end else if (elapsed == LIMIT-1) begin
            if (!fault) begin
                fault <= 1'b1;
                if (fault_count != 8'hff)
                    fault_count <= fault_count + 1'b1;
            end
            // Saturate the elapsed timer and do NOT count every clock.
        end else begin
            elapsed <= elapsed + 1'b1;
        end
    end
endmodule
