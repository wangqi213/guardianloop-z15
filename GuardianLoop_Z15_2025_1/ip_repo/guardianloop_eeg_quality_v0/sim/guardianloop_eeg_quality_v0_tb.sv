`timescale 1 ns / 1 ps

module guardianloop_eeg_quality_v0_tb;
    logic s_axi_aclk;
    logic s_axi_aresetn;
    logic [8:0] s_axi_awaddr;
    logic [2:0] s_axi_awprot;
    logic s_axi_awvalid;
    wire s_axi_awready;
    logic [31:0] s_axi_wdata;
    logic [3:0] s_axi_wstrb;
    logic s_axi_wvalid;
    wire s_axi_wready;
    wire [1:0] s_axi_bresp;
    wire s_axi_bvalid;
    logic s_axi_bready;
    logic [8:0] s_axi_araddr;
    logic [2:0] s_axi_arprot;
    logic s_axi_arvalid;
    wire s_axi_arready;
    wire [31:0] s_axi_rdata;
    wire [1:0] s_axi_rresp;
    wire s_axi_rvalid;
    logic s_axi_rready;
    logic [127:0] s_axis_tdata;
    logic s_axis_tvalid;
    wire s_axis_tready;
    logic s_axis_tlast;
    wire quality_valid;
    wire [7:0] valid_channel_mask;
    wire [31:0] reason_code;
    wire result_ready;
    integer error_count;
    integer sample_index;
    logic [31:0] read_data;

    localparam [8:0] CONTROL       = 9'h000;
    localparam [8:0] WINDOW        = 9'h004;
    localparam [8:0] MIN_SAMPLES   = 9'h008;
    localparam [8:0] MAX_ABS       = 9'h00C;
    localparam [8:0] MAX_SAT       = 9'h010;
    localparam [8:0] MAX_MEAN      = 9'h014;
    localparam [8:0] REQUIRED_MASK = 9'h018;
    localparam [8:0] STATUS        = 9'h020;
    localparam [8:0] VALID_MASK    = 9'h024;
    localparam [8:0] REASON        = 9'h028;
    localparam [8:0] COMPLETED     = 9'h02C;
    localparam [8:0] CHANNEL0      = 9'h040;

    guardianloop_eeg_quality_v0_v1_0 dut (
        .s_axi_aclk, .s_axi_aresetn,
        .s_axi_awaddr, .s_axi_awprot, .s_axi_awvalid, .s_axi_awready,
        .s_axi_wdata, .s_axi_wstrb, .s_axi_wvalid, .s_axi_wready,
        .s_axi_bresp, .s_axi_bvalid, .s_axi_bready,
        .s_axi_araddr, .s_axi_arprot, .s_axi_arvalid, .s_axi_arready,
        .s_axi_rdata, .s_axi_rresp, .s_axi_rvalid, .s_axi_rready,
        .s_axis_tdata, .s_axis_tvalid, .s_axis_tready, .s_axis_tlast,
        .quality_valid, .valid_channel_mask, .reason_code, .result_ready
    );

    always #5 s_axi_aclk = ~s_axi_aclk;

    task automatic expect_equal(input logic [31:0] actual, input logic [31:0] expected, input string label);
        begin
            if (actual !== expected) begin
                error_count = error_count + 1;
                $display("FAIL: %s expected=%08h actual=%08h", label, expected, actual);
            end else $display("PASS: %s value=%08h", label, actual);
        end
    endtask

    task automatic axi_write(input logic [8:0] addr, input logic [31:0] data);
        begin
            @(negedge s_axi_aclk);
            s_axi_awaddr = addr; s_axi_awvalid = 1'b1;
            s_axi_wdata = data; s_axi_wstrb = 4'hF; s_axi_wvalid = 1'b1;
            while (!(s_axi_awvalid && s_axi_awready && s_axi_wvalid && s_axi_wready)) @(posedge s_axi_aclk);
            @(negedge s_axi_aclk);
            s_axi_awvalid = 1'b0; s_axi_wvalid = 1'b0; s_axi_bready = 1'b1;
            while (!s_axi_bvalid) @(posedge s_axi_aclk);
            if (s_axi_bresp != 2'b00) begin error_count = error_count + 1; $display("FAIL: AXI write response"); end
            @(negedge s_axi_aclk); s_axi_bready = 1'b0;
        end
    endtask

    task automatic axi_read(input logic [8:0] addr, output logic [31:0] data);
        begin
            @(negedge s_axi_aclk);
            s_axi_araddr = addr; s_axi_arvalid = 1'b1;
            while (!(s_axi_arvalid && s_axi_arready)) @(posedge s_axi_aclk);
            @(negedge s_axi_aclk);
            s_axi_arvalid = 1'b0; s_axi_rready = 1'b1;
            while (!s_axi_rvalid) @(posedge s_axi_aclk);
            data = s_axi_rdata;
            if (s_axi_rresp != 2'b00) begin error_count = error_count + 1; $display("FAIL: AXI read response"); end
            @(negedge s_axi_aclk); s_axi_rready = 1'b0;
        end
    endtask

    task automatic send_point(
        input logic signed [15:0] c0, input logic signed [15:0] c1,
        input logic signed [15:0] c2, input logic signed [15:0] c3,
        input logic signed [15:0] c4, input logic signed [15:0] c5,
        input logic signed [15:0] c6, input logic signed [15:0] c7,
        input logic last
    );
        begin
            @(negedge s_axi_aclk);
            s_axis_tdata = {c7,c6,c5,c4,c3,c2,c1,c0};
            s_axis_tlast = last;
            s_axis_tvalid = 1'b1;
            while (!(s_axis_tvalid && s_axis_tready)) @(posedge s_axi_aclk);
            @(negedge s_axi_aclk);
            s_axis_tvalid = 1'b0;
            s_axis_tlast = 1'b0;
        end
    endtask

    task automatic clear_and_configure(input logic [31:0] control);
        begin
            axi_write(CONTROL, control | 32'h10); // preserve enables and W1C prior result.
            axi_write(WINDOW, 32'd250);
            axi_write(MIN_SAMPLES, 32'd250);
            axi_write(MAX_ABS, 32'd1000);
            axi_write(MAX_SAT, 32'd0);
            axi_write(MAX_MEAN, 32'd100);
            axi_write(REQUIRED_MASK, 32'hFF);
        end
    endtask

    initial begin
        s_axi_aclk = 1'b0; s_axi_aresetn = 1'b0;
        s_axi_awaddr = '0; s_axi_awprot = '0; s_axi_awvalid = 1'b0;
        s_axi_wdata = '0; s_axi_wstrb = '0; s_axi_wvalid = 1'b0; s_axi_bready = 1'b0;
        s_axi_araddr = '0; s_axi_arprot = '0; s_axi_arvalid = 1'b0; s_axi_rready = 1'b0;
        s_axis_tdata = '0; s_axis_tvalid = 1'b0; s_axis_tlast = 1'b0;
        error_count = 0;
        repeat (5) @(posedge s_axi_aclk);
        s_axi_aresetn = 1'b1;

        // 1. Normal 250-point window: all eight channels valid.
        clear_and_configure(32'h0000_000F);
        for (sample_index = 0; sample_index < 250; sample_index = sample_index + 1)
            send_point(16'sd10,16'sd20,16'sd30,16'sd40,16'sd50,16'sd60,16'sd70,16'sd80, sample_index == 249);
        axi_read(STATUS, read_data); expect_equal(read_data, 32'h0000_0007, "normal result status");
        axi_read(VALID_MASK, read_data); expect_equal(read_data, 32'h0000_00FF, "normal valid mask");
        axi_read(REASON, read_data); expect_equal(read_data, 32'h0000_0000, "normal reason");
        axi_read(COMPLETED, read_data); expect_equal(read_data, 32'd250, "normal completed samples");
        axi_read(CHANNEL0, read_data); expect_equal(read_data, 32'd250, "normal channel zero sample count");

        // 2. One clipped channel: ch3 hits signed positive rail once.
        clear_and_configure(32'h0000_0007);
        for (sample_index = 0; sample_index < 250; sample_index = sample_index + 1)
            send_point(16'sd10,16'sd10,16'sd10,(sample_index == 7) ? 16'sh7FFF : 16'sd10,16'sd10,16'sd10,16'sd10,16'sd10, sample_index == 249);
        axi_read(VALID_MASK, read_data); expect_equal(read_data, 32'h0000_00F7, "clipped channel mask");
        axi_read(REASON, read_data); expect_equal(read_data, 32'h0000_0016, "clipped channel reason");

        // 3. One DC/mean-absolute-offset channel: ch5 mean is above configured 100.
        clear_and_configure(32'h0000_0009);
        for (sample_index = 0; sample_index < 250; sample_index = sample_index + 1)
            send_point(16'sd10,16'sd10,16'sd10,16'sd10,16'sd10,16'sd200,16'sd10,16'sd10, sample_index == 249);
        axi_read(VALID_MASK, read_data); expect_equal(read_data, 32'h0000_00DF, "DC-offset channel mask");
        axi_read(REASON, read_data); expect_equal(read_data, 32'h0000_0018, "DC-offset reason");

        // 4. TLAST closes an insufficient 20-sample window.
        clear_and_configure(32'h0000_0001);
        for (sample_index = 0; sample_index < 20; sample_index = sample_index + 1)
            send_point(16'sd10,16'sd10,16'sd10,16'sd10,16'sd10,16'sd10,16'sd10,16'sd10, sample_index == 19);
        axi_read(VALID_MASK, read_data); expect_equal(read_data, 32'h0000_0000, "insufficient window mask");
        axi_read(REASON, read_data); expect_equal(read_data, 32'h0000_0011, "insufficient window reason");
        axi_read(COMPLETED, read_data); expect_equal(read_data, 32'd20, "insufficient completed samples");

        // 5. Two channels exceed amplitude limit, so the whole required mask is invalid.
        clear_and_configure(32'h0000_0003);
        for (sample_index = 0; sample_index < 250; sample_index = sample_index + 1)
            send_point(16'sd2000,16'sd2000,16'sd10,16'sd10,16'sd10,16'sd10,16'sd10,16'sd10, sample_index == 249);
        axi_read(STATUS, read_data); expect_equal(read_data, 32'h0000_0005, "multi-failure status has valid=0");
        axi_read(VALID_MASK, read_data); expect_equal(read_data, 32'h0000_00FC, "multi-failure channel mask");
        axi_read(REASON, read_data); expect_equal(read_data, 32'h0000_0012, "multi-failure reason");

        if (error_count == 0) begin
            $display("GuardianLoop EEG Quality v0 simulation PASSED");
            $finish;
        end else begin
            $display("GuardianLoop EEG Quality v0 simulation FAILED with %0d error(s)", error_count);
            $fatal(1);
        end
    end
endmodule
