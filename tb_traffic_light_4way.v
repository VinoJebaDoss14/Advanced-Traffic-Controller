`timescale 1ns/1ps

module tb_traffic_light_4way;

// Inputs
reg clk;
reg rst_n;
reg emergency_in;

// Outputs
wire [2:0] light_north;
wire [2:0] light_south;
wire [2:0] light_east;
wire [2:0] light_west;
wire ped_walk;

// Instantiate the DUT (Device Under Test)
traffic_light_4way dut (
    .clk(clk),
    .rst_n(rst_n),
    .emergency_in(emergency_in),
    .light_north(light_north),
    .light_south(light_south),
    .light_east(light_east),
    .light_west(light_west),
    .ped_walk(ped_walk)
);

// Clock generation (10ns period = 100 MHz)
always #5 clk = ~clk;

// Task to display current light states
task display_lights;
    $display("Time: %0t | North: %b | South: %b | East: %b | West: %b | Pedestrian Walk: %b",
              $time, light_north, light_south, light_east, light_west, ped_walk);
endtask

initial begin
    // Initialize signals
    clk = 0;
    rst_n = 0;
    emergency_in = 0;

    // Apply reset
    #20;
    rst_n = 1;

    // Normal traffic operation for a few seconds
    repeat (80) begin
        @(posedge clk);
        if (dut.clk_enable) display_lights();
    end

    // Trigger emergency
    $display("---- Emergency Signal Activated ----");
    emergency_in = 1;

    // Emergency mode duration
    repeat (10) begin
        @(posedge clk);
        if (dut.clk_enable) display_lights();
    end

    // Deactivate emergency signal
    $display("---- Emergency Signal Cleared ----");
    emergency_in = 0;

    // Resume normal operation
    repeat (40) begin
        @(posedge clk);
        if (dut.clk_enable) display_lights();
    end

    $display("---- Simulation Complete ----");
    
end

endmodule
