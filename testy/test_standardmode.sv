`define DRIVER testbench.dv_i2c
`define TARGET testbench.tg_i2c
`define MAIL   testbench.dv_i2c.tr_mailbox
`define RAND   testbench.dv_i2c.i2c_cfg
`define TRANS  testbench.test_tr

import transaction_class::*;
import i2c_timing_types_pkg::*;

module test;

timeunit 1ns;
timeprecision 1ps;

i2c_timing_cfg_t timing_cfg;

real time1, time2;
real t_scl_rise, t_last_sda_change;

bit EXPECTED_SCL_PERIOD;
bit EXPECTED_SCL_FREQ;
bit EXPECTED_START_HOLD;
bit EXPECTED_START_SETUP;
bit EXPECTED_STOP_SETUP;
bit EXPECTED_TBUF;
bit EXPECTED_DATA_SETUP;
bit EXPECTED_DATA_HOLD;
bit EXPECTED_DATA_VALID;

event assert_chk_SCLPeriod;
event assert_chk_SCLClockFreq;
event assert_chk_startHoldTime;
event assert_chk_repeatedStartSetupTime;
event assert_chk_stopSetUpTime;
event assert_chk_stopStartFreeTime;
event assert_chk_dataHoldSetUpTime;
event assert_chk_dataValidTime;

always @(testbench.SDA)
    t_last_sda_change = $realtime;

always @(posedge testbench.SCL)
    t_scl_rise = $realtime;

initial begin
    Transaction tr;

    timing_cfg = get_cfg(MODE_STD);

    `RAND = new();
    if (!`RAND.randomize())
        $error("Randomization failed");

    `DRIVER.HIGH_PERIOD_SCL  = `RAND.high_period;
    `DRIVER.LOW_PERIOD_SCL   = `RAND.low_period;
    `DRIVER.DATA_SETUP_TIME  = `RAND.setup_time;
    `DRIVER.START_SETUP_TIME = `RAND.start_setup_time;
    `DRIVER.START_HOLD_TIME  = `RAND.start_hold_time;
    `DRIVER.STOP_SETUP_TIME  = `RAND.stop_setup_time;
    `DRIVER.DATA_HOLD_TIME   = `DRIVER.LOW_PERIOD_SCL - `DRIVER.DATA_SETUP_TIME;

    #100ns;

    tr = new(
        .address(7'b0010000),
        .rw(0),
        .data({8'b10101010, 8'b11100011})
    );

    `MAIL.put(tr);

    //chk_startHoldTime
    wait(DRIVER.phase == M_START);

    @(negedge testbench.SDA iff (testbench.SCL == 1));
    time1 = $realtime();

    @(negedge testbench.SCL);
    time2 = $realtime();

    EXPECTED_START_HOLD =
        ((time2 - time1) >= timing_cfg.T_HD_STA_MIN);

    -> assert_chk_startHoldTime;

    //chk_repeatedStartSetupTime
    @(negedge testbench.SDA iff (testbench.SCL == 1));
    EXPECTED_START_SETUP =
        (($realtime - t_scl_rise) >= timing_cfg.T_SU_STA_MIN);

    -> assert_chk_repeatedStartSetupTime;

    //chk_SCLPeriod
    @(negedge testbench.SCL);
    time1 = $realtime();

    @(negedge testbench.SCL);
    time2 = $realtime();

    EXPECTED_SCL_PERIOD =
        ((time2 - time1) >= timing_cfg.T_SCL_MIN);

    -> assert_chk_SCLPeriod;

    //chk_SCLClockFreq
    EXPECTED_SCL_FREQ =
        (1e9 / (time2 - time1)) <= timing_cfg.SCLClockFreq_MAX;

    -> assert_chk_SCLClockFreq;

    //chk_dataHoldSetUpTime

    wait(DRIVER.phase == M_DATA_RX || DRIVER.phase == M_DATA_TX )

    @(posedge testbench.SCL);
    EXPECTED_DATA_SETUP =
        ((t_scl_rise - t_last_sda_change) >= timing_cfg.T_SU_DAT_MIN);

    EXPECTED_DATA_HOLD = 1'b1;

    -> assert_chk_dataHoldSetUpTime;

    //chk_dataValidTime
    @(posedge testbench.SCL);

    EXPECTED_DATA_VALID =
        (!$changed(testbench.SDA));

    -> assert_chk_dataValidTime;

    //chk_stopSetUpTime
    wait(DRIVER.phase = M_STOP)

    @(posedge testbench.SDA iff (testbench.SCL == 1));
    EXPECTED_STOP_SETUP =
        (($realtime - t_scl_rise) >= timing_cfg.T_SU_STO_MIN);

    -> assert_chk_stopSetUpTime;

    //chk_stopStartFreeTime
    time1 = $realtime();

    @(negedge testbench.SDA iff (testbench.SCL == 1));
    time2 = $realtime();

    EXPECTED_TBUF =
        ((time2 - time1) >= timing_cfg.T_BUF_MIN);

    -> assert_chk_stopStartFreeTime;

    

    #25us;
    $finish;
end


always @(assert_chk_SCLPeriod)
    chk_SCLPeriod:
    assert(EXPECTED_SCL_PERIOD) $display(chk_SCLPeriod PASSED!); else $error("chk_SCLPeriod FAILED");

always @(assert_chk_SCLClockFreq)
    chk_SCLClockFreq:
    assert(EXPECTED_SCL_FREQ) $display(chk_SCLClockFreq PASSED!); else $error("chk_SCLClockFreq FAILED");

always @(assert_chk_startHoldTime)
    chk_startHoldTime:
    assert(EXPECTED_START_HOLD) $display(chk_startHoldTime PASSED!); else $error("chk_startHoldTime FAILED");

always @(assert_chk_repeatedStartSetupTime)
    chk_repeatedStartSetupTime:
    assert(EXPECTED_START_SETUP) $display(chk_repeatedStartSetupTime PASSED!); else $error("chk_repeatedStartSetupTime FAILED");

always @(assert_chk_stopSetUpTime)
    chk_stopSetUpTime:
    assert(EXPECTED_STOP_SETUP) $display(chk_stopSetUpTime PASSED!); else $error("chk_stopSetUpTime FAILED");

always @(assert_chk_stopStartFreeTime)
    chk_stopStartFreeTime:
    assert(EXPECTED_TBUF) $display(chk_stopStartFreeTime PASSED!); else $error("chk_stopStartFreeTime FAILED");

always @(assert_chk_dataHoldSetUpTime)
    chk_dataHoldSetUpTime:
    assert(EXPECTED_DATA_SETUP && EXPECTED_DATA_HOLD) $display(chk_dataHoldSetUpTime PASSED!); else $error("chk_dataHoldSetUpTime FAILED");

always @(assert_chk_dataValidTime)
    chk_dataValidTime:
    assert(EXPECTED_DATA_VALID) $display(chk_dataValidTime PASSED!); else $error("chk_dataValidTime FAILED");

endmodule
