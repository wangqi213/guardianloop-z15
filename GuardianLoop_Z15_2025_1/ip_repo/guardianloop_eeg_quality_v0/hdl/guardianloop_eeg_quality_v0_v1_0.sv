`timescale 1 ns / 1 ps

// GuardianLoop EEG quality v0.
// One AXI4-Stream transfer is one time point: {Ch8, Ch7, ..., Ch1}, signed int16.
// All arithmetic is integer fixed point in the transport unit of 0.01 uV/LSB.
module guardianloop_eeg_quality_v0_v1_0 #(
    parameter integer C_S_AXI_DATA_WIDTH = 32,
    parameter integer C_S_AXI_ADDR_WIDTH = 9
) (
    input  wire                              s_axi_aclk,
    input  wire                              s_axi_aresetn,

    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_awaddr,
    input  wire [2:0]                        s_axi_awprot,
    input  wire                              s_axi_awvalid,
    output wire                              s_axi_awready,
    input  wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_wdata,
    input  wire [(C_S_AXI_DATA_WIDTH/8)-1:0] s_axi_wstrb,
    input  wire                              s_axi_wvalid,
    output wire                              s_axi_wready,
    output wire [1:0]                        s_axi_bresp,
    output wire                              s_axi_bvalid,
    input  wire                              s_axi_bready,
    input  wire [C_S_AXI_ADDR_WIDTH-1:0]     s_axi_araddr,
    input  wire [2:0]                        s_axi_arprot,
    input  wire                              s_axi_arvalid,
    output wire                              s_axi_arready,
    output wire [C_S_AXI_DATA_WIDTH-1:0]     s_axi_rdata,
    output wire [1:0]                        s_axi_rresp,
    output wire                              s_axi_rvalid,
    input  wire                              s_axi_rready,

    input  wire [127:0]                      s_axis_tdata,
    input  wire                              s_axis_tvalid,
    output wire                              s_axis_tready,
    input  wire                              s_axis_tlast,

    output wire                              quality_valid,
    output wire [7:0]                        valid_channel_mask,
    output wire [31:0]                       reason_code,
    output wire                              result_ready
);

    localparam integer ADDR_LSB = 2;
    localparam [8:0] REG_CONTROL            = 9'h000;
    localparam [8:0] REG_WINDOW_SAMPLES     = 9'h004;
    localparam [8:0] REG_MIN_SAMPLES        = 9'h008;
    localparam [8:0] REG_MAX_ABS            = 9'h00C;
    localparam [8:0] REG_MAX_SAT_COUNT      = 9'h010;
    localparam [8:0] REG_MAX_MEAN_ABS       = 9'h014;
    localparam [8:0] REG_REQUIRED_MASK      = 9'h018;
    localparam [8:0] REG_RESULT_STATUS      = 9'h020;
    localparam [8:0] REG_VALID_MASK          = 9'h024;
    localparam [8:0] REG_REASON_CODE         = 9'h028;
    localparam [8:0] REG_COMPLETED_SAMPLES  = 9'h02C;
    localparam [8:0] REG_WINDOW_SEQUENCE    = 9'h030;
    localparam [8:0] REG_CHANNEL_BASE       = 9'h040;
    localparam integer CHANNEL_STRIDE        = 9'h020;

    // STATUS / reason bits are intentionally diagnostic rather than clinical.
    localparam [31:0] REASON_INSUFFICIENT = 32'h0000_0001;
    localparam [31:0] REASON_ABS_LIMIT    = 32'h0000_0002;
    localparam [31:0] REASON_SATURATION   = 32'h0000_0004;
    localparam [31:0] REASON_MEAN_ABS     = 32'h0000_0008;
    localparam [31:0] REASON_REQUIRED_CH  = 32'h0000_0010;

    reg [C_S_AXI_ADDR_WIDTH-1:0] awaddr_reg;
    reg                           awaddr_valid_reg;
    reg [31:0]                    wdata_reg;
    reg [3:0]                     wstrb_reg;
    reg                           wdata_valid_reg;
    reg                           bvalid_reg;
    reg                           rvalid_reg;
    reg [31:0]                    rdata_reg;
    integer                       byte_index;

    // CTRL: bit0 capture_enable; bit1 abs_limit_enable; bit2 saturation_limit_enable;
    // bit3 mean_abs_limit_enable; bit4 is write-one-to-clear result/working state.
    reg        capture_enable_reg;
    reg        abs_limit_enable_reg;
    reg        saturation_limit_enable_reg;
    reg        mean_abs_limit_enable_reg;
    reg [15:0] window_samples_reg;
    reg [15:0] min_samples_reg;
    reg [15:0] max_abs_reg;
    reg [15:0] max_saturation_count_reg;
    reg [31:0] max_mean_abs_reg;
    reg [7:0]  required_valid_mask_reg;

    reg [15:0] work_sample_count [0:7];
    reg [16:0] work_max_abs      [0:7];
    reg [15:0] work_sat_count    [0:7];
    reg [47:0] work_sum_abs      [0:7];

    reg [15:0] result_sample_count [0:7];
    reg [16:0] result_max_abs      [0:7];
    reg [15:0] result_sat_count    [0:7];
    reg [31:0] result_mean_abs     [0:7];
    reg [7:0]  result_flags        [0:7];

    reg [15:0] completed_samples_reg;
    reg [31:0] window_sequence_reg;
    reg        quality_valid_reg;
    reg [7:0]  valid_channel_mask_reg;
    reg [31:0] reason_code_reg;
    reg        result_ready_reg;

    // Window finalisation is deliberately sequential.  The original design
    // divided eight 48-bit sums in the same cycle that accepted TLAST.  That
    // created an ~90 ns DMA-to-result combinational path at a 50 MHz clock.
    reg        finalize_active_reg;
    reg [3:0]  finalize_channel_reg;
    reg [15:0] finalize_sample_count_reg;
    reg [47:0] finalize_sum_abs [0:7];
    reg [7:0]  finalize_valid_mask_reg;
    reg [31:0] finalize_reason_reg;

    // One unsigned 48-by-16 restoring divider, shared by all eight channels.
    // It consumes 48 clocks per channel while S_AXIS_TREADY is low.
    reg        divide_active_reg;
    reg [5:0]  divide_count_reg;
    reg [47:0] divide_dividend_reg;
    reg [48:0] divide_remainder_reg;
    reg [47:0] divide_quotient_reg;
    reg [15:0] divide_denominator_reg;

    integer channel_index;
    integer read_channel_index;
    reg [15:0] next_sample_count;
    reg [16:0] next_abs;
    reg [16:0] next_max_abs;
    reg [15:0] next_sat_count;
    reg [47:0] next_sum_abs;
    reg        close_window;

    reg [7:0]  finalized_channel_flags;
    reg [7:0]  finalized_valid_mask;
    reg [31:0] finalized_reason;

    wire [48:0] divide_shifted_remainder =
        {divide_remainder_reg[47:0], divide_dividend_reg[47]};
    wire divide_subtract = divide_shifted_remainder >= {33'd0, divide_denominator_reg};
    wire [48:0] divide_next_remainder = divide_subtract ?
        (divide_shifted_remainder - {33'd0, divide_denominator_reg}) : divide_shifted_remainder;
    wire [47:0] divide_next_quotient = {divide_quotient_reg[46:0], divide_subtract};
    wire [16:0] stream_ch0_abs = s_axis_tdata[15] ?
        {1'b0, (~s_axis_tdata[15:0]) + 16'd1} : {1'b0, s_axis_tdata[15:0]};
    wire [47:0] stream_ch0_next_sum = work_sum_abs[0] + stream_ch0_abs;

    wire stream_accept = s_axis_tvalid && s_axis_tready;
    wire clear_result_write = awaddr_valid_reg && wdata_valid_reg && !bvalid_reg &&
                              (awaddr_reg == REG_CONTROL) && wstrb_reg[0] && wdata_reg[4];

    assign s_axi_awready = s_axi_aresetn && !awaddr_valid_reg && !bvalid_reg;
    assign s_axi_wready  = s_axi_aresetn && !wdata_valid_reg && !bvalid_reg;
    assign s_axi_bvalid  = bvalid_reg;
    assign s_axi_bresp   = 2'b00;
    assign s_axi_arready = s_axi_aresetn && !rvalid_reg;
    assign s_axi_rvalid  = rvalid_reg;
    assign s_axi_rresp   = 2'b00;
    assign s_axi_rdata   = rdata_reg;

    // Input is accepted only while the software has explicitly enabled capture.
    assign s_axis_tready = s_axi_aresetn && capture_enable_reg && !finalize_active_reg;
    assign quality_valid = quality_valid_reg;
    assign valid_channel_mask = valid_channel_mask_reg;
    assign reason_code = reason_code_reg;
    assign result_ready = result_ready_reg;

    // AXI4-Lite write channel and configuration storage.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            awaddr_reg <= '0;
            awaddr_valid_reg <= 1'b0;
            wdata_reg <= '0;
            wstrb_reg <= '0;
            wdata_valid_reg <= 1'b0;
            bvalid_reg <= 1'b0;
            capture_enable_reg <= 1'b0;
            abs_limit_enable_reg <= 1'b0;
            saturation_limit_enable_reg <= 1'b0;
            mean_abs_limit_enable_reg <= 1'b0;
            window_samples_reg <= 16'd250;
            min_samples_reg <= 16'd250;
            max_abs_reg <= 16'd0;
            max_saturation_count_reg <= 16'd0;
            max_mean_abs_reg <= 32'd0;
            required_valid_mask_reg <= 8'hFF;
        end else begin
            if (s_axi_awvalid && s_axi_awready) begin
                awaddr_reg <= s_axi_awaddr;
                awaddr_valid_reg <= 1'b1;
            end
            if (s_axi_wvalid && s_axi_wready) begin
                wdata_reg <= s_axi_wdata;
                wstrb_reg <= s_axi_wstrb;
                wdata_valid_reg <= 1'b1;
            end
            if (awaddr_valid_reg && wdata_valid_reg && !bvalid_reg) begin
                case (awaddr_reg)
                    REG_CONTROL: begin
                        if (wstrb_reg[0]) begin
                            capture_enable_reg <= wdata_reg[0];
                            abs_limit_enable_reg <= wdata_reg[1];
                            saturation_limit_enable_reg <= wdata_reg[2];
                            mean_abs_limit_enable_reg <= wdata_reg[3];
                        end
                    end
                    REG_WINDOW_SAMPLES: begin
                        if (wstrb_reg[0]) window_samples_reg[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) window_samples_reg[15:8] <= wdata_reg[15:8];
                    end
                    REG_MIN_SAMPLES: begin
                        if (wstrb_reg[0]) min_samples_reg[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) min_samples_reg[15:8] <= wdata_reg[15:8];
                    end
                    REG_MAX_ABS: begin
                        if (wstrb_reg[0]) max_abs_reg[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) max_abs_reg[15:8] <= wdata_reg[15:8];
                    end
                    REG_MAX_SAT_COUNT: begin
                        if (wstrb_reg[0]) max_saturation_count_reg[7:0] <= wdata_reg[7:0];
                        if (wstrb_reg[1]) max_saturation_count_reg[15:8] <= wdata_reg[15:8];
                    end
                    REG_MAX_MEAN_ABS: begin
                        for (byte_index = 0; byte_index < 4; byte_index = byte_index + 1)
                            if (wstrb_reg[byte_index]) max_mean_abs_reg[byte_index*8 +: 8] <= wdata_reg[byte_index*8 +: 8];
                    end
                    REG_REQUIRED_MASK: if (wstrb_reg[0]) required_valid_mask_reg <= wdata_reg[7:0];
                    default: ;
                endcase
                awaddr_valid_reg <= 1'b0;
                wdata_valid_reg <= 1'b0;
                bvalid_reg <= 1'b1;
            end else if (bvalid_reg && s_axi_bready) begin
                bvalid_reg <= 1'b0;
            end
        end
    end

    // EEG window accumulator and sequential finaliser.  A completed window is
    // frozen first; the shared divider then evaluates one channel over 48
    // cycles.  This keeps every DMA stream-accept path to add/compare logic.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn || clear_result_write) begin
            completed_samples_reg <= 16'd0;
            window_sequence_reg <= 32'd0;
            quality_valid_reg <= 1'b0;
            valid_channel_mask_reg <= 8'd0;
            reason_code_reg <= 32'd0;
            result_ready_reg <= 1'b0;
            finalize_active_reg <= 1'b0;
            finalize_channel_reg <= 4'd0;
            finalize_sample_count_reg <= 16'd0;
            finalize_valid_mask_reg <= 8'd0;
            finalize_reason_reg <= 32'd0;
            divide_active_reg <= 1'b0;
            divide_count_reg <= 6'd0;
            divide_dividend_reg <= 48'd0;
            divide_remainder_reg <= 49'd0;
            divide_quotient_reg <= 48'd0;
            divide_denominator_reg <= 16'd1;
            for (channel_index = 0; channel_index < 8; channel_index = channel_index + 1) begin
                work_sample_count[channel_index] <= 16'd0;
                work_max_abs[channel_index] <= 17'd0;
                work_sat_count[channel_index] <= 16'd0;
                work_sum_abs[channel_index] <= 48'd0;
                finalize_sum_abs[channel_index] <= 48'd0;
                result_sample_count[channel_index] <= 16'd0;
                result_max_abs[channel_index] <= 17'd0;
                result_sat_count[channel_index] <= 16'd0;
                result_mean_abs[channel_index] <= 32'd0;
                result_flags[channel_index] <= 8'd0;
            end
        end else begin
            if (stream_accept) begin
                next_sample_count = work_sample_count[0] + 16'd1;
                close_window = s_axis_tlast ||
                    (window_samples_reg != 16'd0 && next_sample_count >= window_samples_reg);
                for (channel_index = 0; channel_index < 8; channel_index = channel_index + 1) begin
                    if (s_axis_tdata[channel_index*16 + 15])
                        next_abs = {1'b0, (~s_axis_tdata[channel_index*16 +: 16]) + 16'd1};
                    else
                        next_abs = {1'b0, s_axis_tdata[channel_index*16 +: 16]};
                    next_max_abs = (next_abs > work_max_abs[channel_index]) ?
                        next_abs : work_max_abs[channel_index];
                    next_sat_count = work_sat_count[channel_index] +
                        ((s_axis_tdata[channel_index*16 +: 16] == 16'h7FFF ||
                          s_axis_tdata[channel_index*16 +: 16] == 16'h8000) ? 16'd1 : 16'd0);
                    next_sum_abs = work_sum_abs[channel_index] + next_abs;
                    if (close_window) begin
                        result_sample_count[channel_index] <= next_sample_count;
                        result_max_abs[channel_index] <= next_max_abs;
                        result_sat_count[channel_index] <= next_sat_count;
                        result_mean_abs[channel_index] <= 32'd0;
                        result_flags[channel_index] <= 8'd0;
                        finalize_sum_abs[channel_index] <= next_sum_abs;
                        work_sample_count[channel_index] <= 16'd0;
                        work_max_abs[channel_index] <= 17'd0;
                        work_sat_count[channel_index] <= 16'd0;
                        work_sum_abs[channel_index] <= 48'd0;
                    end else begin
                        work_sample_count[channel_index] <= next_sample_count;
                        work_max_abs[channel_index] <= next_max_abs;
                        work_sat_count[channel_index] <= next_sat_count;
                        work_sum_abs[channel_index] <= next_sum_abs;
                    end
                end
                if (close_window) begin
                    completed_samples_reg <= next_sample_count;
                    window_sequence_reg <= window_sequence_reg + 32'd1;
                    quality_valid_reg <= 1'b0;
                    valid_channel_mask_reg <= 8'd0;
                    reason_code_reg <= 32'd0;
                    result_ready_reg <= 1'b0;
                    finalize_active_reg <= 1'b1;
                    finalize_channel_reg <= 4'd0;
                    finalize_sample_count_reg <= next_sample_count;
                    finalize_valid_mask_reg <= 8'd0;
                    finalize_reason_reg <= 32'd0;
                    divide_active_reg <= 1'b1;
                    divide_count_reg <= 6'd0;
                    divide_dividend_reg <= stream_ch0_next_sum;
                    divide_remainder_reg <= 49'd0;
                    divide_quotient_reg <= 48'd0;
                    divide_denominator_reg <= (next_sample_count == 16'd0) ? 16'd1 : next_sample_count;
                end
            end else if (divide_active_reg) begin
                divide_remainder_reg <= divide_next_remainder;
                divide_dividend_reg <= {divide_dividend_reg[46:0], 1'b0};
                divide_quotient_reg <= divide_next_quotient;
                if (divide_count_reg == 6'd47) begin
                    finalized_channel_flags = 8'd0;
                    finalized_valid_mask = finalize_valid_mask_reg;
                    finalized_reason = finalize_reason_reg;
                    if (finalize_sample_count_reg < min_samples_reg) begin
                        finalized_channel_flags[4] = 1'b1;
                        finalized_reason = finalized_reason | REASON_INSUFFICIENT;
                    end
                    if (abs_limit_enable_reg && result_max_abs[finalize_channel_reg] > max_abs_reg) begin
                        finalized_channel_flags[1] = 1'b1;
                        finalized_reason = finalized_reason | REASON_ABS_LIMIT;
                    end
                    if (saturation_limit_enable_reg && result_sat_count[finalize_channel_reg] > max_saturation_count_reg) begin
                        finalized_channel_flags[2] = 1'b1;
                        finalized_reason = finalized_reason | REASON_SATURATION;
                    end
                    if (mean_abs_limit_enable_reg && divide_next_quotient[31:0] > max_mean_abs_reg) begin
                        finalized_channel_flags[3] = 1'b1;
                        finalized_reason = finalized_reason | REASON_MEAN_ABS;
                    end
                    if (finalized_channel_flags[4:1] == 4'd0) begin
                        finalized_channel_flags[0] = 1'b1;
                        finalized_valid_mask[finalize_channel_reg] = 1'b1;
                    end
                    result_mean_abs[finalize_channel_reg] <= divide_next_quotient[31:0];
                    result_flags[finalize_channel_reg] <= finalized_channel_flags;
                    finalize_valid_mask_reg <= finalized_valid_mask;
                    finalize_reason_reg <= finalized_reason;
                    if (finalize_channel_reg == 4'd7) begin
                        if ((finalized_valid_mask & required_valid_mask_reg) != required_valid_mask_reg)
                            finalized_reason = finalized_reason | REASON_REQUIRED_CH;
                        valid_channel_mask_reg <= finalized_valid_mask;
                        reason_code_reg <= finalized_reason;
                        quality_valid_reg <= ((finalized_valid_mask & required_valid_mask_reg) == required_valid_mask_reg);
                        result_ready_reg <= 1'b1;
                        finalize_active_reg <= 1'b0;
                        divide_active_reg <= 1'b0;
                    end else begin
                        finalize_channel_reg <= finalize_channel_reg + 4'd1;
                        divide_count_reg <= 6'd0;
                        divide_dividend_reg <= finalize_sum_abs[finalize_channel_reg + 4'd1];
                        divide_remainder_reg <= 49'd0;
                        divide_quotient_reg <= 48'd0;
                    end
                end else begin
                    divide_count_reg <= divide_count_reg + 6'd1;
                end
            end
        end
    end

    // AXI4-Lite read channel. Channel statistic blocks are 0x40 + channel*0x20.
    always @(posedge s_axi_aclk) begin
        if (!s_axi_aresetn) begin
            rvalid_reg <= 1'b0;
            rdata_reg <= 32'd0;
        end else begin
            if (s_axi_arvalid && s_axi_arready) begin
                rvalid_reg <= 1'b1;
                rdata_reg <= 32'd0;
                case (s_axi_araddr)
                    REG_CONTROL: rdata_reg <= {28'd0, mean_abs_limit_enable_reg, saturation_limit_enable_reg, abs_limit_enable_reg, capture_enable_reg};
                    REG_WINDOW_SAMPLES: rdata_reg <= {16'd0, window_samples_reg};
                    REG_MIN_SAMPLES: rdata_reg <= {16'd0, min_samples_reg};
                    REG_MAX_ABS: rdata_reg <= {16'd0, max_abs_reg};
                    REG_MAX_SAT_COUNT: rdata_reg <= {16'd0, max_saturation_count_reg};
                    REG_MAX_MEAN_ABS: rdata_reg <= max_mean_abs_reg;
                    REG_REQUIRED_MASK: rdata_reg <= {24'd0, required_valid_mask_reg};
                    REG_RESULT_STATUS: rdata_reg <= {29'd0, result_ready_reg, quality_valid_reg, capture_enable_reg};
                    REG_VALID_MASK: rdata_reg <= {24'd0, valid_channel_mask_reg};
                    REG_REASON_CODE: rdata_reg <= reason_code_reg;
                    REG_COMPLETED_SAMPLES: rdata_reg <= {16'd0, completed_samples_reg};
                    REG_WINDOW_SEQUENCE: rdata_reg <= window_sequence_reg;
                    default: begin
                        if (s_axi_araddr >= REG_CHANNEL_BASE && s_axi_araddr < (REG_CHANNEL_BASE + 8*CHANNEL_STRIDE)) begin
                            read_channel_index = (s_axi_araddr - REG_CHANNEL_BASE) / CHANNEL_STRIDE;
                            case ((s_axi_araddr - REG_CHANNEL_BASE) % CHANNEL_STRIDE)
                                9'h000: rdata_reg <= {16'd0, result_sample_count[read_channel_index]};
                                9'h004: rdata_reg <= {15'd0, result_max_abs[read_channel_index]};
                                9'h008: rdata_reg <= {16'd0, result_sat_count[read_channel_index]};
                                9'h00C: rdata_reg <= result_mean_abs[read_channel_index];
                                9'h010: rdata_reg <= {24'd0, result_flags[read_channel_index]};
                                default: rdata_reg <= 32'd0;
                            endcase
                        end
                    end
                endcase
            end else if (rvalid_reg && s_axi_rready) begin
                rvalid_reg <= 1'b0;
            end
        end
    end

endmodule
