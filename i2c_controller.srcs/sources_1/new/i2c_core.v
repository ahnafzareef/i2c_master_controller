`timescale 1ns / 1ps
//////////////////////////////////////////////////////////////////////////////////
// Company: 
// Engineer: 
// 
// Create Date: 06/24/2026 10:50:42 AM
// Design Name: 
// Module Name: i2c_core
// Project Name: 
// Target Devices: 
// Tool Versions: 
// Description: 
// 
// Dependencies: 
// 
// Revision:
// Revision 0.01 - File Created
// Additional Comments:
// 
//////////////////////////////////////////////////////////////////////////////////


module i2c_core(
    input clk,
    input reset,
    
    //slot
    input cs,
    input read,
    input write,
    
    //The wr and rd data address is the values the cpu writes into the address or reads out
    //the addr is the register location dependent on what it looks to send. Loc0,1,2...
    
    input [4:0] addr,
    
    //read data is output, the driver must send the info to the cpu
    //write is input, the driver must retrieve the info from the cpu to send to the location
    input [31:0] wr_data,
    output wire [31:0] rd_data,
    
    output tri scl,
    output tri sda
    );
    
    //signals
    reg [15:0] dvsr_reg;
    wire wr_i2c, wr_dvsr; //fired when cpu tries to write, wr_dvsr goes high when cpu writes to loc 1 and loc 2 for i2c write
    wire [7:0] dout;
    wire ready, ack;
    
    //instantiate controler
    i2c_master i2c_0 (
    .din(wr_data[7:0]), 
    .cmd(wr_data[10:8]), //write data loc 2 of 10:8
    .dvsr(dvsr_reg), 
    .done_main(),
    .clk(clk),
    .reset(reset),
    .scl(scl),
    .sda(sda),
    .dout(dout),
    .ready_main(ready),
    .ack(ack)
    );
    
    always @(posedge clk, posedge reset) begin
        if (reset)
            dvsr_reg <= 0;
        else begin
            if (wr_dvsr)
                dvsr_reg <= wr_data[15:0]; //from the specs bits 15:0 on location of write data register
        end
    end
    
    //write to divisor loc when chip selected, write enabled and the memory mapped address is 1, 0 is for reading
    
    assign wr_dvsr = cs & write & addr[1:0] == 2'b01;
    assign wr_i2c = cs && write && addr[1:0] == 2'b10;
    
    //32 bits but only send 10 for i2c, so pad left with 22 0's, send ack, ready then the data
    assign rd_data = {22'b0, ack, ready,dout};
endmodule
