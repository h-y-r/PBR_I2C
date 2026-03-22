`define DRIVER testbench.dv_i2c
`define TARGET testbench.tg_i2c
`define MAIL testbench.dv_i2c.tr_mailbox
`define RAND testbench.dv_i2c.i2c_cfg
`define TRANS testbench.test_tr
module tst_combinedFormatForMemoryAddressing_write;

// Deklaracje zmiennych

initial begin
	Transaction tr_addr;
	Transaction tr_write;

	RAND = new();
	if (!RAND.randomize()) begin
	$error("blad");
	end

	DRIVER.HIGH_PERIOD_SCL = RAND.high_period;
	DRIVER.LOW_PERIOD_SCL  = RAND.low_period;
	DRIVER.DATA_SETUP_TIME = RAND.setup_time;
	DRIVER.RAND_STOP_BIT = RAND.rand_bit;
	DRIVER.START_SETUP_TIME = RAND.start_setup_time;
	DRIVER.START_HOLD_TIME = RAND.start_hold_time;
	DRIVER.STOP_SETUP_TIME = RAND.stop_setup_time;
	DRIVER.DATA_HOLD_TIME = DRIVER.LOW_PERIOD_SCL - DRIVER.DATA_SETUP_TIME;	
	#100ns;
	tr_addr = new(
        .address(7'b0010000), 
        .rw(0), 
        .data({8'b00000001}) //zmienic jak bedzie target z pamiecia
    );

    tr_write = new(
    	.address(7'b0010000),
    	.rw(0),
    	.data({8'b11001010})
    );
	
	`MAIL.put(tr_addr);
	`MAIL.put(tr_write);
	
	#25us;
	$finish();
end


endmodule