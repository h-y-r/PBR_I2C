`timescale 1ns/10ps
import transaction_class::*;

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
    //.rst(rst),
    //.clk(clk),
    //.data_send(16'hDEAD), 
    .sda(SDA),      
    .scl(SCL),    
    //.data_received()
  );
  
  driver_I2C dv_i2c(
    .clk(clk),
    .SDA(SDA),
    .SCL(SCL)
  );

   I2C_Config i2c_cfg;
	

  Transaction test_tr;
  Transaction test_tr2;	  
  initial begin
    i2c_cfg = new();
     if (!i2c_cfg.randomize()) begin
       $error("blad");
     end
	  
     dv_i2c.HIGH_PERIOD_SCL = i2c_cfg.high_period;
     dv_i2c.LOW_PERIOD_SCL  = i2c_cfg.low_period;
     dv_i2c.DATA_SETUP_TIME = i2c_cfg.setup_time;
     dv_i2c.RAND_STOP_BIT = i2c_cfg.rand_bit;
     dv_i2c.START_SETUP_TIME = i2c_cfg.start_setup_time;
     dv_i2c.START_HOLD_TIME = i2c_cfg.start_hold_time;
     dv_i2c.STOP_SETUP_TIME = i2c_cfg.stop_setup_time;
     dv_i2c.DATA_HOLD_TIME = dv_i2c.LOW_PERIOD_SCL - dv_i2c.DATA_SETUP_TIME;
    
    $dumpfile("dump.vcd");
    $dumpvars(0,testbench);
    #10;
    rst = 1;    
    #10;     
    rst = 0; 
    #10;
    rst = 1;
    test_tr = new(
        .address(7'b0000111), 
        .rw(0), 
        .data({8'b10101010, 8'b11100011})
    );

    #1 dv_i2c.tr_mailbox.put(test_tr);

    // UWAGA Z FEEDBACKU: Jeśli chcesz wysłać kolejną transakcję zmieniając tylko jeden parametr,
    // zamiast robić new(), zrób:
    // test_tr.address = 7'h55;
    // dv_i2c.tr_mailbox.put(test_tr);
    
    //test_tr = new(7'b0000111, 0, ,{8'b10101010, 8'b11100011});
    //#1 dv_i2c.tr_mailbox.put(test_tr);
    //#10 test_tr2 = new(7'b0000111, 1, 1);
    //#1 dv_i2c.tr_mailbox.put(test_tr2);
    //dv_i2c.writeTransaction(7'b0000111, 8'b10101010);
    //dv_i2c.readTransaction(7'b0000111);
    //dv_i2c.writeRandomStop(7'b0000111, 8'b10101010, 2);
   
    $display("Simulation Finished.");

    #1000000
    $finish(0);
  end

endmodule
