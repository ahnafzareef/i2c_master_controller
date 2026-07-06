`timescale 1ns / 1ps

module i2c_tb;
   //Commands
   localparam [2:0] START_CMD=0, WR_CMD=1, RD_CMD=2, STOP_CMD=3, RESTART_CMD=4;
   localparam [6:0] SLAVE_ADDR = 7'h50; //Some Fake Slave Device for Testing
   localparam [7:0] SLAVE_RDATA = 8'h3C; //Some Fake Contents the slave will hold when master reading
   
   reg clk, reset, wr_i2c; //wr_i2c pulse for start
   reg [2:0] cmd;
   reg [7:0] din;
   reg [15:0] dvsr;
   wire [7:0] dout;
   wire ready_main, done_main, ack;
   tri scl, sda;
   
   integer pass = 0, fail = 0; //hold passes and failures
   
   //Open Drain
   pullup(scl);
   pullup(sda);
   
   i2c_master dut(
      .clk(clk), .reset(reset), .wr_i2c(wr_i2c), .cmd(cmd), .din(din),
      .dvsr(dvsr), .dout(dout), .ready_main(ready_main), .done_main(done_main),
      .ack(ack), .scl(scl), .sda(sda)
   );
   
   //Clock
   initial clk = 0;
   always #5 clk = ~clk; //100 MHZ
   
   task run (input [2:0] c, input [7:0] d); //task to start a run
        begin
            @(posedge clk); cmd=c; din=d; wr_i2c =1;
            @(posedge clk); wr_i2c=0;
            
            //if master accepts: ready = 0; then when done ready = 1;
            wait(ready_main==0); wait(ready_main==1);
        end
    endtask
    
    //task to check if the output is correct
    
    task check(input condition, input [255:0] msg);
        begin
            if (condition) begin
               pass = pass+1;
               $display(" Passed: %0s", msg);
            end else begin
                fail = fail + 1;
                $display(" Failed: %0s", msg);
            end
        end
    endtask
    
    
    //Emulating the Slave Device
    reg slave_driver; //signal to drive the slave
    reg [7:0] slave_memory; //the location the master writes to.
    reg [3:0] slave_bit_cnt; //track what bit slave is on
    reg slave_active;
    reg slave_first; //first byte is address
    reg slave_rw; //determine read or write
    reg slave_match; //if address same
    reg [7:0] slave_tx;
    
    //define behaviour of the slave. 
    initial begin
        slave_driver = 0; slave_active=0; slave_bit_cnt = 0; slave_first =0;
        slave_rw =0; slave_match=0; slave_tx=SLAVE_RDATA; slave_memory =0;
    end
    
    //start and stop
    always @(negedge sda) begin
        if (scl == 1'b1) begin //start
            slave_active = 1; slave_bit_cnt = 0; slave_first = 1; slave_driver = 0; slave_match = 0;
            slave_rw =0;
        end
    end
    
    always @(posedge sda) begin //stop
        if(scl==1'b1) begin
            slave_active =0; slave_bit_cnt =0; slave_driver = 0; slave_match =0;
            slave_first =0; slave_rw=0;
        end
    
    end
    
    
    always @(posedge scl) if (slave_active) begin
        if (slave_bit_cnt < 8) begin
            if(!(slave_match && slave_rw && !slave_first)) begin
                slave_memory = {slave_memory[6:0], (sda===1'b0)?1'b0:1'b1};
            end
            slave_bit_cnt = slave_bit_cnt + 1;
       end else begin
        slave_bit_cnt = 0;
        slave_first = 0;
       end    
    end
    
    always @(negedge scl) if (slave_active) begin
        if (slave_bit_cnt == 8) begin
            if (slave_first) begin
                slave_match = (slave_memory[7:1] == SLAVE_ADDR); //8th bit is rw flag
                slave_rw = slave_memory[0];
                slave_driver = slave_match;
            end else if (!slave_rw) begin
                slave_driver = slave_match;
            end else begin
                slave_driver =0;
            end
        end else begin
            if (slave_match && slave_rw && !slave_first) begin
                slave_driver = (slave_tx[7 - slave_bit_cnt] == 1'b0);
            end else begin
                slave_driver = 0;
            end
        end
   end
   
   
   initial begin
      reset=1; wr_i2c=0; cmd=0; din=0; dvsr=16'd8;
      repeat(4) @(posedge clk);
      reset=0;
      wait(ready_main==1);

      $display("TEST 1: write 0xC3 then 0x55 to slave 0x50");
      run(START_CMD, 8'h00);
      run(WR_CMD, {SLAVE_ADDR, 1'b0});
      check(ack==1'b0, "address byte ACKed");
      run(WR_CMD, 8'hC3);
      check(ack==1'b0, "data 0xC3 ACKed");
      run(WR_CMD, 8'h55);
      check(ack==1'b0, "data 0x55 ACKed");
      run(STOP_CMD, 8'h00);

      $display("TEST 2: address wrong slave 0x10 (expect NACK)");
      run(START_CMD, 8'h00);
      run(WR_CMD, {7'h10, 1'b0});
      check(ack==1'b1, "wrong address NACKed");
      run(STOP_CMD, 8'h00);

      $display("TEST 3: read one byte from slave 0x50 (expect 0x%02h)", SLAVE_RDATA);
      run(START_CMD, 8'h00);
      run(WR_CMD, {SLAVE_ADDR, 1'b1});
      check(ack==1'b0, "address byte ACKed");
      run(RD_CMD, 8'h01);
      check(dout==SLAVE_RDATA, "received byte matches slave data");
      run(STOP_CMD, 8'h00);

      $display("=====================================");
      $display("RESULT: %0d passed, %0d failed", pass, fail);
      $display("=====================================");
      $finish;
   end

   initial begin #500000; $display("TIMEOUT"); $finish; end
   initial begin $dumpfile("i2c_tb.vcd"); $dumpvars(0, i2c_tb); end

   
endmodule