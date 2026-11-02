// DDR -> HDMI: infrequent frame snapshot, held unchanged until next frame.
// Toggle crosses 2 FFs. Payload crosses 2 FFs, is used only when the
// synchronized toggle changes, i.e. after the stable payload has settled.
// Source must hold all fields until the next toggle (one displayed frame).
module frame_id_snapshot_cdc (
    input wire         clk,
    input wire         rst_n,
    input wire [15:0]  src_capture_id,
    input wire [15:0]  src_display_id,
    input wire [11:0]  src_lag_frames,
    input wire         src_valid,
    input wire         src_toggle,
    output reg [15:0]  capture_id,
    output reg [15:0]  display_id,
    output reg [11:0]  lag_frames,
    output reg         valid,
    output reg         update_pulse
);
    reg [44:0] bus_meta, bus_sync;
    reg tog_meta, tog_sync, tog_seen;
    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            bus_meta <= 45'd0; bus_sync <= 45'd0;
            tog_meta <= 1'b0; tog_sync <= 1'b0; tog_seen <= 1'b0;
            capture_id <= 16'd0; display_id <= 16'd0;
            lag_frames <= 12'd0; valid <= 1'b0; update_pulse <= 1'b0;
        end else begin
            bus_meta <= {src_capture_id,src_display_id,src_lag_frames,src_valid};
            bus_sync <= bus_meta;
            tog_meta <= src_toggle;
            tog_sync <= tog_meta;
            update_pulse <= 1'b0;
            if (tog_sync != tog_seen) begin
                tog_seen <= tog_sync;
                {capture_id,display_id,lag_frames,valid} <= bus_sync;
                update_pulse <= 1'b1;
            end
        end
    end
endmodule
