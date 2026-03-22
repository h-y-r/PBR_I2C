`define DRIVER testbench.dv_i2c
`define TARGET testbench.tg_i2c
`define MAIL testbench.dv_i2c.tr_mailbox
`define RAND testbench.dv_i2c.i2c_cfg
`define TRANS testbench.test_tr
module tst_readTransaction;

// Deklaracje zmiennych
bit DATA_STABLE = 1;
bit NO_STOP = 1;
bit RW_BIT;

bit prev_sda;
realtime DATA_UNSTABLE_time;
realtime STOP_time;

event assert_chk_dataStableWhenSCLHigh;
event assert_chk_RWBitRead;
event assert_chk_targetDoesNotGenerateStop;


initial begin
	Transaction tr;

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
	
	tr = new(
        .address(7'b0010000), 
        .rw(1), 
        .r_len(2)
    );
	
	`MAIL.put(tr);
	
	wait (`DRIVER.phase == M_ACK_ADDR);
	RW_BIT = (`TARGET.rw);
	-> assert_chk_RWBitRead;
	wait (`DRIVER.phase == M_DONE);
	-> assert_chk_dataStableWhenSCLHigh;
	-> assert_chk_targetDoesNotGenerateStop;
	$finish();
end

always @(posedge testbench.clk) begin
	if(testbench.SCL == 1 && DATA_STABLE && testbench.SDA != prev_sda && (`DRIVER.phase != M_STOP || `DRIVER.phase != M_START)) begin
		DATA_UNSTABLE_time = $realtime();
		DATA_STABLE = 0;
	end
	if(prev_sda == 0 && testbench.SDA != prev_sda && `DRIVER.phase != M_STOP && NO_STOP) begin
		STOP_time = $realtime();
		NO_STOP = 0;
	end 
	prev_sda = testbench.SDA;
end

always @(assert_chk_dataStableWhenSCLHigh) begin
	chk_dataStableWhenSCLHigh : assert(DATA_STABLE) $display("chk_dataStableWhenSCLHigh PASSED");
								else $error("chk_dataStableWhenSCLHigh FAILED at time %0t", DATA_UNSTABLE_time);
end

always @(assert_chk_targetDoesNotGenerateStop) begin
	chk_targetDoesNotGenerateStop : assert(NO_STOP) $display("chk_targetDoesNotGenerateStop PASSED");
									else $error("chk_targetDoesNotGenerateStop FAILED at time %0t", STOP_time);
end

always @(assert_chk_RWBitRead) begin
	chk_RWBitRead : assert(RW_BIT) $display("chk_RWBitRead PASSED");
					else $error("chk_RWBitRead FAILED");
end

endmodule