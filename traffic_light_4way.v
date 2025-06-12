// Verilog project: Verilog code for 4-way highway intersection traffic light controller
// with added Pedestrian Scramble Crossing Phase and Emergency Handling

module traffic_light_4way(
    light_north,   // North approach lights
    light_south,   // South approach lights
    light_east,    // East approach lights
    light_west,    // West approach lights
    ped_walk,      // Output: High when pedestrian crossing is allowed
    emergency_in,  // NEW INPUT: High when an emergency is detected
    clk,           // System clock (e.g., 50 MHz)
    rst_n          // Active-low reset
);

// --- Light Output Encoding ---
// Each light output is 3 bits: [Red, Yellow, Green]
parameter GREEN = 3'b001; // Light is Green
parameter YELLOW = 3'b010; // Light is Yellow
parameter RED = 3'b100;    // Light is Red

// --- State Definitions for the Finite State Machine (FSM) ---
// IMPORTANT FIX: Changed parameter widths to 4'b to match reg [3:0] state/next_state
// This ensures that PED_S and EMERGENCY_S are correctly interpreted and not truncated.
parameter NG_S = 4'b0000, // North Green (all others Red)
          NY_S = 4'b0001, // North Yellow (all others Red)
          EG_S = 4'b0010, // East Green (all others Red)
          EY_S = 4'b0011, // East Yellow (all others Red)
          SG_S = 4'b0100, // South Green (all others Red)
          SY_S = 4'b0101, // South Yellow (all others Red)
          WG_S = 4'b0110, // West Green (all others Red)
          WY_S = 4'b0111, // West Yellow (all others Red)
          PED_S = 4'b1000, // Pedestrian Scramble (all vehicle lights Red, ped_walk HIGH)
          EMERGENCY_S = 4'b1001; // NEW STATE: Emergency (all vehicle lights Red, ped_walk LOW)

// --- Traffic Light Durations (in seconds) ---
// These parameters define how long each green and yellow phase lasts
parameter GREEN_DURATION = 10;     // Duration for green light in seconds
parameter YELLOW_DURATION = 3;     // Duration for yellow light in seconds
parameter PEDESTRIAN_DURATION = 10; // Duration for pedestrian scramble in seconds

// --- Inputs and Outputs ---
input clk;             // Main clock signal, typically 50 MHz in FPGA applications
input rst_n;           // Active-low reset signal. When low, the system resets to its initial state.
input emergency_in;    // NEW INPUT: Signal from emergency vehicle detector (active high)

output reg [2:0] light_north; // 3-bit output for North-bound traffic lights
output reg [2:0] light_south; // 3-bit output for South-bound traffic lights
output reg [2:0] light_east;  // 3-bit output for East-bound traffic lights
output reg [2:0] light_west;  // 3-bit output for West-bound traffic lights
output reg ped_walk;         // Single-bit output for pedestrian walk signal

// --- Internal Registers and Wires ---
reg [3:0] state, next_state; // Current and next state registers for the FSM (now 4 bits for PED_S and EMERGENCY_S)
reg [3:0] saved_state;       // NEW: Register to store the state before entering emergency mode
reg [27:0] count = 0;        // Counter for generating a 1-second clock enable pulse from 50 MHz
reg [3:0] timer_count = 0;   // Counter for timing the green, yellow, and pedestrian phases
reg timer_reset = 0;         // Control signal to reset the timer_count for a new phase
wire clk_enable;             // Wire that pulses high for one clock cycle every second

// --- 1-Second Clock Enable Generation ---
// This always block creates a 'clk_enable' pulse approximately once every second.
// For a 50 MHz clock, 50,000,000 cycles equals 1 second.
// For simulation/testbench, 'count == 3' is used to speed up the process (1 pulse every 4 clock cycles).
always @(posedge clk) begin
    count <= count + 1; // Increment the counter on each rising clock edge
    // Check if 'count' has reached the value corresponding to 1 second
    // In a real FPGA with 50MHz clock, this would be: if(count == 50_000_000 - 1)
    if (count == 3) // For testbench: counts 0, 1, 2, 3. On 3, it pulses and resets.
        count <= 0; // Reset the counter to 0
end
// Assign 'clk_enable' to be high only when 'count' reaches the specified value
assign clk_enable = (count == 3); // High when 'count' is 3 (for testbench)

// --- Phase Timer Logic ---
// This block manages the 'timer_count' which tracks the duration of each light phase.
// It increments only when 'clk_enable' is high (i.e., once per second).
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin // Asynchronous reset
        timer_count <= 0; // Reset timer count on system reset
    end else if (clk_enable) begin // Only update when a 1-second pulse occurs
        if (timer_reset) begin // If a state transition signals a timer reset
            timer_count <= 0; // Reset the timer for the new phase
        end else begin
            timer_count <= timer_count + 1; // Increment timer count
        end
    end
end

// --- State Register Update ---
// This sequential block updates the current state of the FSM on each positive clock edge.
// It also handles the asynchronous reset.
always @(posedge clk or negedge rst_n) begin
    if (~rst_n) begin
        state <= NG_S;        // On reset, go to the initial state (North Green)
        saved_state <= NG_S;  // Initialize saved_state to a safe default
    end else
        state <= next_state; // Otherwise, update to the next state
end

// --- Finite State Machine (FSM) Logic and Light Outputs ---
// This combinational block determines the 'next_state' and sets the traffic light outputs
// based on the 'current state', 'timer_count', and 'emergency_in' signal.
always @(*) begin
    // Default assignments for all outputs (most common/safe state)
    // All lights are RED by default, unless explicitly set to GREEN or YELLOW in a state.
    light_north = RED;
    light_south = RED;
    light_east = RED;
    light_west = RED;
    ped_walk = 0;        // Pedestrian walk signal is OFF by default

    // Default next_state is to stay in current state; overridden by specific transitions
    next_state = state;
    timer_reset = 0;    // Default: do not reset the timer (unless specified by a state transition)

    // --- Emergency Handling (Highest Precedence) ---
    // If an emergency is detected, immediately force all lights to RED
    if (emergency_in) begin
        // If we are NOT already in the emergency state, save the current state
        if (state != EMERGENCY_S) begin
            saved_state = state; // Store the state we are leaving
        end
        next_state = EMERGENCY_S; // Force the next state to EMERGENCY_S
        // Lights are already RED, ped_walk is 0 by default, which is correct for emergency
    end else begin // No emergency currently active or emergency has just cleared
        // --- Normal FSM State Transitions ---
        // This 'case' statement defines the normal operational sequence
        case (state)
            NG_S: begin // State: North Green
                light_north = GREEN;
                if (clk_enable && (timer_count == GREEN_DURATION - 1)) begin
                    next_state = NY_S;
                    timer_reset = 1; // Reset timer for the next phase
                end
            end
            NY_S: begin // State: North Yellow
                light_north = YELLOW;
                if (clk_enable && (timer_count == YELLOW_DURATION - 1)) begin
                    next_state = EG_S;
                    timer_reset = 1;
                end
            end
            EG_S: begin // State: East Green
                light_east = GREEN;
                if (clk_enable && (timer_count == GREEN_DURATION - 1)) begin
                    next_state = EY_S;
                    timer_reset = 1;
                end
            end
            EY_S: begin // State: East Yellow
                light_east = YELLOW;
                if (clk_enable && (timer_count == YELLOW_DURATION - 1)) begin
                    next_state = SG_S;
                    timer_reset = 1;
                end
            end
            SG_S: begin // State: South Green
                light_south = GREEN;
                if (clk_enable && (timer_count == GREEN_DURATION - 1)) begin
                    next_state = SY_S;
                    timer_reset = 1;
                end
            end
            SY_S: begin // State: South Yellow
                light_south = YELLOW;
                if (clk_enable && (timer_count == YELLOW_DURATION - 1)) begin
                    next_state = WG_S;
                    timer_reset = 1;
                end
            end
            WG_S: begin // State: West Green
                light_west = GREEN;
                if (clk_enable && (timer_count == GREEN_DURATION - 1)) begin
                    next_state = WY_S;
                    timer_reset = 1;
                end
            end
            WY_S: begin // State: West Yellow
                light_west = YELLOW;
                if (clk_enable && (timer_count == YELLOW_DURATION - 1)) begin
                    next_state = PED_S; // Transition to Pedestrian Scramble
                    timer_reset = 1;
                end
            end
            PED_S: begin // State: Pedestrian Scramble
                ped_walk = 1; // Set ped_walk HIGH during this state
                if (clk_enable && (timer_count == PEDESTRIAN_DURATION - 1)) begin
                    next_state = NG_S; // Return to North Green
                    timer_reset = 1;
                end
            end
            EMERGENCY_S: begin // NEW STATE: Currently in Emergency Mode
                // Lights are already RED (by default assignment outside case)
                // ped_walk is already 0 (by default assignment outside case)
                // If emergency_in becomes LOW (checked by the outer 'if-else' block),
                // we will transition out of this state.
                // The 'else' block ensures next_state is set to saved_state when emergency_in is 0
                next_state = saved_state; // When emergency_in goes low, return to the saved state
                timer_reset = 1;          // Reset timer for the resumed state to start fresh
            end
            default: begin // Safety net for unexpected states
                next_state = NG_S; // Go to a known safe state
                timer_reset = 1;
            end
        endcase
    end
end

endmodule
