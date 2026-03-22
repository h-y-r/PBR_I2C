`define DRIVER testbench.dv_i2c
`define TARGET testbench.tg_i2c
`define MAIL testbench.dv_i2c.tr_mailbox
`define RAND testbench.dv_i2c.i2c_cfg
`define TRANS testbench.test_tr
`define TARGET_BITS testbench.tg_i2c.data_send //ostatnie do zmieniania, latwiej bedzie dla roznych targetow z definicja

import transaction_class::*;

module test;

property ADRESS_10BIT;
	@(posedge testbench.SCL)
	((`DRIVER.phase == M_ADDR_10BIT) && (`DRIVER.bit_idx == BIT_ACK)) |-> (testbench.SDA == 1'b0); // ACK po 1 bajcie adresu
endproperty

property WRITE_DATA_10BIT;
    @(posedge testbench.SCL)
    ((`DRIVER.phase == M_ADDR_10BIT) && (`DRIVER.bit_idx == BIT_ACK) && (testbench.SDA == 1'b0)) // ACK po 1 bajcie adresu
    ##[1:$]
    (`DRIVER.phase == M_DATA_TX) |-> (`DRIVER.bit_idx >= 0); // robi write
endproperty

property READ_DATA_10BIT;
    @(posedge testbench.SCL)
    ((`DRIVER.phase == M_ADDR_10BIT) && (`DRIVER.bit_idx == BIT_ACK) && (testbench.SDA == 1'b0)) // ACK po 1 bajcie adresu
    ##[1:$]
    (`DRIVER.phase == M_DATA_RX) |-> (`DRIVER.bit_idx >= 0); // robi read
endproperty


initial begin
	Transaction tr;

	RAND = new();
	if (!RAND.randomize()) begin
	$error("blad");
	end

	`DRIVER.HIGH_PERIOD_SCL = RAND.high_period;
	`DRIVER.LOW_PERIOD_SCL  = RAND.low_period;
	`DRIVER.DATA_SETUP_TIME = RAND.setup_time;
	`DRIVER.RAND_STOP_BIT = RAND.rand_bit;
	`DRIVER.START_SETUP_TIME = RAND.start_setup_time;
	`DRIVER.START_HOLD_TIME = RAND.start_hold_time;
	`DRIVER.STOP_SETUP_TIME = RAND.stop_setup_time;
	`DRIVER.DATA_HOLD_TIME = DRIVER.LOW_PERIOD_SCL - DRIVER.DATA_SETUP_TIME;	
	#100ns;
		
	`DRIVER.writeTransaction10BIT(10'b0000000111, 8'b10101010);
	#BUFF_TIME;
	`DRIVER.readTransaction10BIT(10'b0000000111);
	
	`MAIL.put(tr);
	#25us;
end
	
chk_adress10Bit: assert property (ADRESS_10BIT) $display ("chk_adress10Bit PASSED!");
		else $error("chk_adress10Bit FAILED!");
		
chk_writeData10Bit: assert property (WRITE_DATA_10BIT) $display("chk_writeData10Bit PASSED!");
		else $error("chk_writeData10Bit FAILED!");	

chk_readData10Bit: assert property (READ_DATA_10BIT) $display("chk_readData10Bit PASSED!");
		else $error("chk_readData10Bit FAILED!");
