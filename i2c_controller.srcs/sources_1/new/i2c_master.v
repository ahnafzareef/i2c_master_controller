`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: I2C Controller Project
// Engineer: Ahnaf Zareef
// 
// Create Date: 06/23/2026 10:40:46 AM
// Design Name: I2C Controller
// Module Name: i2c_master
// Project Name: I2C Controller
// Target Devices: ARTY S7 25T
// Tool Versions: Vivado 2025.2
// Description: An I2C controller, half duplex, one master support.
// 
// Dependencies: NONE
// 
// Revision: 1
// Revision 0.01 - File Created
// Additional Comments: Alot of comments, primarily for my learning as I learn. I hope it helps you!
// On the github I also have my notes which include the diagrams I reference in my comments.
// Follow along with the diagrams so you know why I chose to drive certain values high and low.
// If its too small open on goodnotes <3.
//////////////////////////////////////////////////////////////////////////////////


module i2c_master(
    input clk, reset,
    input [7:0] din,
    input [15:0] dvsr,
    input [2:0] cmd,
    input wr_i2c, //this is sent if device wants to start i2c transaction
    output tri scl,
    inout tri sda,
    
    output ack, ready_main, done_main,
    output [7:0] dout
    );
    
    
    //Commands (3-bits for 5 commands)
    localparam START = 3'b000;
    localparam WRITE = 3'b001;
    localparam READ = 3'b010;
    localparam STOP = 3'b011;
    localparam RESTART = 3'b100;
    
    //FSM states
    localparam idle = 0,  hold = 1,  start1 = 2,  start2 = 3,
           data1 = 4, data2 = 5, data3 = 6,  data4 = 7,
           data_end = 8, restart = 9, stop1 = 10, stop2 = 11;
           
    
    //declare our module.
    reg [3:0] state_reg, state_next; //Hold states and Next State
    
    //Creating the internal memory to store then do whatever.
    
    //i2c master clock.
    //count will count upto pre determined quarter or half phase.
    //when the half/qtr phases are hit, it'll signal on what to do
    //count_next is just combinational signal that calculates 
    //what the counter value should be on the very next clock cycle
    //then it determines if it should inc or reset based on curr state
    
    
    //the reason why they all have current and next is because
    //next is where fsm calcs next value, fsm uses this to
    //calculate before the clock tick saves them to current.
    reg [15:0] c_reg, c_next; //these are to generate exact timing intervals like 1/4 and 1/2.
    wire [15:0] qtr, half;
    
    reg [8:0] tx_reg, tx_next;
    reg [8:0] rx_reg, rx_next;
    reg [3:0] cmd_reg, cmd_next;
    reg [3:0] bit_reg, bit_next;
    
    //scl_reg and sda_reg hold the state and out will send it out, Out is the combinatioanl next value signals
    reg sda_out, sda_reg, scl_out,scl_reg, phase;
    reg done, ready;
    wire into, nack; //hold into: reading or writing to slave, and nack
    
    
    
    //output control logic, take from FSM ("what do I drive")
    //buffer for sda and scl
    always @(posedge clk or posedge reset)
        if (reset) begin
            sda_reg <= 0;
            scl_reg <= 0;
        end else begin
            sda_reg <= sda_out;
            scl_reg <= scl_out;
        end
    
    //because the protcol is open drain, its tied HIGH. If we want SCL to be high (aka if register has 1 coming in)
    //that means you set the scl line to be floating, which will tie it to vdd. If scl_reg has 0 coming in
    //then tie it to 0 to set scl as 0;
    assign scl = (scl_reg) ? 1'bz : 1'b0; //wire scl line to the register. 
    
    //sda works same as SCL logic, however the data is 9 bits, where the LSB is the acknowledge
    //For write operations: this acknowledge comes from the slave, so this value must be read so the bit
    //should be a 0 to READ.
    //For read operations: this acknowledge is from the master: so it must WRITE to the slave: so it
    //should be 1
    
    //When the master has to read or listen to the slave (first cond) then into is true,
    //and when its the NINTH BIT AND THE MASTER IS WRITING, WHEN MASTER WRITING THEN IT SHOULD READ THE 
    //ACK FROM THE SLAVE SO THEN AT THAT POINT INTO BECOMES TRUE SO MASTER CAN READ THE ACK and see its done.
    
    assign into = (phase && cmd_reg == READ && bit_reg < 8)|| (phase && cmd_reg == WRITE && bit_reg == 8);
    
    assign sda = (sda_reg || into) ? 1'bz : 1'b0;
    
    
    //output
    //rx_reg is where the recieved bits to send to device accumulate.
    assign dout = rx_reg[8:1]; //last bit is ack
    assign ack = rx_reg[0:0];
    assign nack = din[0]; //this is the ack the master sends to slave during read;
    
    
    //Transmitting The Bytes (Addr, Start, Data, etc)
    
    always @(posedge clk or posedge reset) begin
        if (reset) begin
            state_reg <= idle;
            c_reg <= 0;
            bit_reg   <= 0;
            cmd_reg   <= 0;
            tx_reg    <= 0;
            rx_reg    <= 0;
        end else begin
            state_reg <= state_next;
            c_reg <= c_next;
            bit_reg <= bit_next;
            cmd_reg <= cmd_next;
            tx_reg <= tx_next;
            rx_reg <= rx_next;
        end
    end
    
    assign qtr = dvsr; //half is multiply by 2, which is bit shift left
    assign half = {qtr[14:0], 1'b0};
    
    
    //next state
    always @(*) begin
        state_next = state_reg;
        c_next = c_reg + 1;
        bit_next = bit_reg;
        tx_next = tx_reg;
        rx_next = rx_reg;
        cmd_next = cmd_reg;
        done = 1'b0;
        ready = 1'b0;
        scl_out = 1'b1; //drive high (does nothing) open drain
        sda_out = 1'b1; //drive high (does nothing) open drain
        phase = 1'b0;
        
        case (state_reg) 
        //according to diagram, idle state: scl sda held high
            idle: begin
                ready = 1'b1;
                if (wr_i2c && cmd == START) begin
                    c_next = 0;
                    state_next = start1;
                end
            end
            //start 1: sda becomes low, and scl stays hi
            start1: begin
                sda_out = 1'b0;
                //we want to take every half phase for start, stop, reset
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = start2;
                end
            end
            
            //start2: scl becomes low and sda stays low
            start2: begin
                sda_out = 1'b0;
                scl_out = 1'b0;          
                if(c_reg == qtr) begin
                    c_next = 0;
                    state_next = hold;
                end
            end
                
            //hold: scl low and sda also low.
            hold: begin
                ready = 1'b1;
                sda_out = 1'b0;
                scl_out = 1'b0;
               
               //from hold can go three paths: restart/start, stop or write/read based on cmd;
               if (wr_i2c) begin
                    cmd_next = cmd;
                    c_next = 0;
                    
                    case (cmd)
                        RESTART, START : begin
                            state_next = restart;
                        end 
                        STOP: begin
                            state_next = stop1;
                        end
                        
                        default: begin
                            bit_next = 0; //start at first bit
                            state_next = data1;
                            tx_next = {din, nack}; //to transmit if needed, 8 bits + 1 bit nack;
                        end
                    endcase
               end 
            end
            
            //when transmitting data: sda must be stable when scl is high. Sda cal only change once scl is low.
            //based on the diagram: we can only sample when scl is HIGH and sda is stable: therefore, of the four quarters
            //we have to do both read and writing here in these data states, but what chooses whether its read or write is if into is enabled
            //to read: we can choose to sample at phase 2 (data2) or phase 3(data 3). because scl is high while sda is stable.
            //to write: we are doing ONE BIT with the MSB GOING FIRST FOR 4 PHASES. in the last phase we can remove the MSB
            //From tx_next, shift left and add a 0 at the end so we then read the next bit at [8].
            
            data1: begin
                sda_out =  tx_reg[8]; //MSB FIRST
                scl_out = 1'b0;
                phase = 1'b1;
                
                //once one quarter phase has passed we are onto data2.
                
                if (c_reg == qtr) begin
                    c_next = 0;
                    state_next = data2;
                end
            end
            
            data2: begin
                sda_out = tx_reg[8]; //this entire 4 phases + 4 phases is for one bit only.
                phase = 1'b1;
                
                if (c_reg == qtr) begin
                    c_next = 0;
                    state_next = data3;
                    rx_next = {rx_reg[7:0], sda}; //8 bits with the first 8 of rx net as the 8 of rx and the lsb of sda which is ack
                end
            end
            
            data3: begin
                sda_out = tx_reg[8];
                phase = 1'b1;
                
                if(c_reg == qtr) begin
                    c_next = 0;
                    state_next = data4;
                end
            end
            
            //scl in 4th stage is pulled low
            data4: begin
                sda_out = tx_reg[8];
                scl_out = 1'b0;
                phase = 1'b1;
                
                if (c_reg == qtr) begin
                    c_next = 0;
                    
                    //Last bit check
                    if (bit_reg == 8) begin
                        state_next = data_end;
                        done = 1'b1;
                    end else begin
                        //remove the msb and shift the 7th bit into the place of the 8th and then shift IN 0;
                        tx_next = {tx_reg[7:0], 1'b0}; //tx_reg is 9 bits, dont use bit 8.
                        bit_next = bit_reg + 1;
                        state_next = data1;
                    end
                end
            end
            
            data_end: begin
                //at end sda and scl are low
                sda_out = 1'b0;
                scl_out = 1'b0;
                
                if (c_reg == qtr) begin
                    c_next = 0;
                    state_next = hold; //if another bit or whatever
                end
            end
            
            restart: begin
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = start1;
                end
            end
            
            //stop1 scl is high sda is lo2, at stop2 both are high followed by idle.
            stop1: begin
                sda_out = 1'b0;
                if (c_reg == half) begin
                    c_next = 0;
                    state_next = stop2;
                end
            end
            default: //for stop2 and all other extra stuff just incase
                if (c_reg == half)
                    state_next = idle;
        endcase
    end
    
    assign done_main = done;
    assign ready_main = ready;
endmodule
