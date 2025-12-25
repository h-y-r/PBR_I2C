`timescale 1ns/10ps

module testbench;
  tri1 SCL;
  tri1 SDA;
  pullup(SDA);
  pullup(SCL);

  logic clk;
  logic rst;

  initial clk = 0;
  always #10 clk = ~clk;
  
  target_I2C tg_i2c(
    .rst(rst),
    .clk(clk),
    .data_send(16'hDEAD), 
    .SDA_bidir(SDA),      
    .SCL_bidir(SCL),     
    .data_received()
  );
  
  driver_I2C dv_i2c(
    .clk(clk),
    .SDA(SDA),
    .SCL(SCL)
  );

  initial begin
	$dumpfile("dump.vcd");
    $dumpvars(0,testbench);
    #10;
    rst = 1;    
    #10;     
    rst = 0; 
    #10;
    rst = 1;
    
    dv_i2c.sendStart();
    dv_i2c.sendAddressRW(7'b0000111, 1);
    dv_i2c.getACK();
    dv_i2c.readData();
    dv_i2c.genSCL();
    dv_i2c.genSCL();
    dv_i2c.genSCL();
    //dv_i2c.sendBit(1);

    $display("Simulation Finished.");

    #100000
    $finish(0);
  end

endmodule
