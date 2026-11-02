// Capture-to-display Frame ID tracking for the existing four-slot DDR video
// architecture. No frame ID is written into RGB pixels or the DDR payload:
// the tag is tied to the physical DDR slot selected by video_in/video_out.
//
// All counters, buffer-slot metadata, and comparisons are in the SAME DDR
// clock domain. A coherent snapshot is exported once per displayed frame.
// Frame difference = latest accepted camera SOF ID - DDR read slot frame ID.
// This is frame-age at display-frame scheduling, NOT optical latency in ms.
module frame_id_tracker #(
    parameter integer ID_WIDTH = 16,
    parameter integer LAG_WIDTH = 12
)(
    input  wire                  clk,
    input  wire                  rst_n,
    input  wire                  capture_start,
    input  wire [1:0]            capture_slot,
    input  wire                  display_start,
    input  wire [1:0]            display_slot,
    output reg  [ID_WIDTH-1:0]   snapshot_capture_id,
    output reg  [ID_WIDTH-1:0]   snapshot_display_id,
    output reg  [LAG_WIDTH-1:0]  snapshot_lag_frames,
    output reg                   snapshot_valid,
    output reg                   snapshot_toggle
);
    // Four registers, rather than BRAM, reflect the original DDR ring slots.
    reg [ID_WIDTH-1:0] slot_id [0:3];
    reg [3:0]          slot_valid;
    reg [ID_WIDTH-1:0] latest_capture_id;
    reg [ID_WIDTH-1:0] cap_next;
    reg [ID_WIDTH-1:0] disp_id;
    reg [ID_WIDTH-1:0] delta;
    integer i;

    // Capture event and display event may arrive on the SAME DDR edge.
    // Use the newest capture ID for the age calculation. If the selected
    // read slot is simultaneously being overwritten, invalidate the tag.
    always @* begin
        cap_next = latest_capture_id + {{(ID_WIDTH-1){1'b0}}, capture_start};
        disp_id = slot_id[display_slot];
        delta = cap_next - disp_id;  // intentional modulo 2^ID_WIDTH
    end

    always @(posedge clk or negedge rst_n) begin
        if (!rst_n) begin
            latest_capture_id  <= {ID_WIDTH{1'b0}};
            slot_valid         <= 4'b0000;
            for (i=0; i<4; i=i+1) slot_id[i] <= {ID_WIDTH{1'b0}};
            snapshot_capture_id  <= {ID_WIDTH{1'b0}};
            snapshot_display_id  <= {ID_WIDTH{1'b0}};
            snapshot_lag_frames  <= {LAG_WIDTH{1'b0}};
            snapshot_valid       <= 1'b0;
            snapshot_toggle      <= 1'b0;
        end else begin
            if (capture_start) begin
                latest_capture_id <= cap_next;
                slot_id[capture_slot] <= cap_next;
                slot_valid[capture_slot] <= 1'b1;
            end
            if (display_start) begin
                snapshot_capture_id <= cap_next;
                snapshot_display_id <= disp_id;
                // Prevent misleading numbers while warming up or if a
                // stale buffer is reused / frame tags are inconsistent.
                snapshot_valid <= slot_valid[display_slot] &&
                                  !(capture_start && capture_slot == display_slot) &&
                                  (delta <= {{(ID_WIDTH-LAG_WIDTH){1'b0}},
                                             {LAG_WIDTH{1'b1}}});
                if (slot_valid[display_slot] &&
                    !(capture_start && capture_slot == display_slot) &&
                    (delta <= {{(ID_WIDTH-LAG_WIDTH){1'b0}},
                               {LAG_WIDTH{1'b1}}}))
                    snapshot_lag_frames <= delta[LAG_WIDTH-1:0];
                else
                    snapshot_lag_frames <= {LAG_WIDTH{1'b0}};
                snapshot_toggle <= ~snapshot_toggle;
            end
        end
    end
endmodule
