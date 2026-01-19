`timescale 1ns/10ps

// class I2C_Config;
//   rand realtime high_period;
//   rand realtime low_period;
//   rand realtime setup_time;
//   rand realtime start_setup_time;
//   rand realtime start_hold_time;
//   rand realtime stop_setup_time;
//   rand realtime rand_bit;

//   constraint i2c_time_const {
//     // Min High: 4000ns, Min Low: 4700ns, Min Setup Time: 250ns 
//     high_period inside {[4000:7000]}; 
//     low_period  inside {[4700:7000]};
//     setup_time  inside {[250:4700]};
//	   start_setup_time  inside {[4700:7000]};
//     start_hold_time  inside {[4000:7000]};
//	   stop_setup_time  inside {[4000:7000]};
//	   rand_bit    inside {[0:7]};
//   }
// endclass


//wszystkie funkcje koncza tick przed negedge SCL
module driver_I2C(input logic clk, inout SDA, inout SCL);
  realtime HIGH_PERIOD_SCL = 6000; //min - 4000ns
  realtime LOW_PERIOD_SCL = 6000; //min - 4700ns
  realtime DATA_SETUP_TIME = 4700; //jak dlugo SDA stabilne przed posedge SCL
  realtime DATA_HOLD_TIME = LOW_PERIOD_SCL - DATA_SETUP_TIME; //jak dlugo SDA stabilne po negedge SCL
  realtime RAND_STOP_BIT = 7;
  realtime START_SETUP_TIME = 4700; //min - 4700ns - repeated start
  realtime START_HOLD_TIME = 4000; //min - 4000ns
  realtime STOP_SETUP_TIME = 4000; //min - 4000ns
  realtime BUFF_TIME = 4700; //min - 4700ns - time buffer pomiedzy stop i start
  localparam MAX_BYTES = 32; //max liczba bajtow do burst write

  logic SDA_ctrl = 1;
  logic SCL_ctrl = 1;
  assign SDA = SDA_ctrl ? 1'bz : 1'b0;
  assign SCL = SCL_ctrl ? 1'bz : 1'b0;
  
  bit ack_got = 0;
  bit [7:0] data_got;
  int i;

  // dodane
  typedef enum logic [3:0] {
    M_IDLE,      // idle
    M_START,     // generowanie START
    M_ADDR,      // wysylanie 7-bit addr + rw
    M_ACK_ADDR,  // probkowanie ACK po adresie
    M_DATA_TX,   // wysylanie danych (master->target)
    M_ACK_DATA,  // probkowanie ACK po danych / wysylanie ACK/NACK po read
    M_DATA_RX,   // odczyt danych (target->master)
    M_STOP,      // generowanie STOP
    M_DONE,      // wszystko OK
    M_ERROR      // blad nack po adresie czy cos
  } master_phase_e;

  master_phase_e phase = M_IDLE;

    class Transaction;
    bit [6:0] address;
    bit rw;
    int readlen;
    bit [7:0]data[$];

    function new(bit [6:0] addr, bit rwSet, int r_len = 0, bit [7:0] data_to_send [$] = {});
      address = addr;
      rw = rwSet;
      data = data_to_send;
      readlen = r_len;
    endfunction : new
  endclass

  typedef mailbox #(Transaction) tr_mbx;

  tr_mbx tr_mailbox;
 
  initial begin
   tr_mailbox = new();//mailbox na transakcje
  end

  // konwencja bit_idx
  //   >=0  indeks bitu adresu/danych
  //   -1   slot bitu rw
  //   -2   slot ack/nack
  localparam int BIT_RW  = -1;
  localparam int BIT_ACK = -2;

  int bit_idx  = BIT_ACK;  // poza danymi
  int byte_idx = -1;       // poza burstem
  bit last_ack = 1'b0;     // 1 ack 0 nack
  
  // koniec dodanego

  
  task sendStart();
    begin
      // dodane
      phase    = M_START;
      bit_idx  = BIT_ACK;
      byte_idx = -1;
      // koniec dodanego
	  assert(SCL === 1'b1 && SDA === 1'b1) 
	  	else $error("SDA i SCL muszą być 1!");
		
	  #(HIGH_PERIOD_SCL- START_HOLD_TIME);
      SDA_ctrl = 0;
	  #(START_HOLD_TIME);
    end
  endtask
  
  task sendStop();
    begin
      // dodane
      phase   = M_STOP;
      bit_idx = BIT_ACK;
      // koniec dodanego

      SCL_ctrl = 0;
      #DATA_SETUP_TIME SDA_ctrl = 0;
      #(LOW_PERIOD_SCL - DATA_SETUP_TIME) SCL_ctrl = 1;
	  #(STOP_SETUP_TIME) SDA_ctrl = 1;
	  #(BUFF_TIME);
		
      // dodane
      phase = M_DONE;
      // koniec dodanego
    end
  endtask
  
  task sendBit (input bit data);
    begin
      SCL_ctrl = 0;
      #DATA_HOLD_TIME SDA_ctrl = data;
      #(DATA_SETUP_TIME) SCL_ctrl = 1;
      wait(SCL === 1'b1); //SCL stretch
      #HIGH_PERIOD_SCL;
    end
  endtask
  
  task sendData (input bit [7:0] data);
    begin
        // dodane
        phase = M_DATA_TX;
        // koniec dodanego

      	for (i = 7; i >= 0; i--) begin
          // dodane
          bit_idx = i;
          // koniec dodanego

          sendBit(data[i]);
        end

        // dodane
        bit_idx  = BIT_ACK;
        ack_got  = 0;
        // koniec dodanego
    end
  endtask
  
  task sendAddressRW(input bit [6:0] addr, input bit rw);
    begin
      // dodane
      phase    = M_ADDR;
      byte_idx = -1;
      // koniec dodanego

      for (i = 6; i >= 0; i--) begin
        // dodane
        bit_idx = i;
        // koniec dodanego

        sendBit(addr[i]);
      end

      // dodane
      bit_idx = BIT_RW;
      // koniec dodanego

      sendBit(rw);

      // dodane
      bit_idx  = BIT_ACK;
      SDA_ctrl = 1;
      // koniec dodanego
    end
  endtask
  
  task genSCL();
    begin
      SCL_ctrl = 0;
      #LOW_PERIOD_SCL SCL_ctrl = 1;
      wait(SCL === 1'b1); //SCL stretch
      #HIGH_PERIOD_SCL;
    end
  endtask
  
  // dodane ???? ack po danych i po adresie
  // task getACK(input bit is_addr_ack = 1'b0);
  //   begin
  //      phase   = is_addr_ack ? M_ACK_ADDR : M_ACK_DATA;
  //      bit_idx = BIT_ACK;

  //      SCL_ctrl = 0;
  //      #LOW_PERIOD_SCL SCL_ctrl = 1;
  //      wait(SCL === 1'b1); //SCL stretch
	 //   #1 begin
  //        ack_got  = ~SDA;     // sda 0 -> ack 1 ------ sda 1 -> nack 0
  //        last_ack = ack_got;  
  //      end
	 //   #(HIGH_PERIOD_SCL - 1);

  //      // jesli nack to eror ---- sprawdzic czy sie nie wysra w burstcie
  //      if (!last_ack) phase = M_ERROR;
  //   end
  // endtask
  // koniec dodanego
task getACK(input bit is_addr_ack = 1'b0);
    begin
       phase   = is_addr_ack ? M_ACK_ADDR : M_ACK_DATA;
       bit_idx = BIT_ACK;

       SCL_ctrl = 0;
       #LOW_PERIOD_SCL SCL_ctrl = 1;
       wait(SCL === 1'b1); // SCL stretch
       #1; 

       if (SDA === 1'b0) begin
           // 0 -> ACK
           ack_got = 1'b1; 
       end 
       else if (SDA === 1'bz || SDA === 1'b1) begin
           //Z lub 1 -> NACK
           ack_got = 1'b0; 
       end 
       else begin
           //X -> błąd/NACK
           ack_got = 1'b0;
           $warning("[I2C DRIVER] SDA is X during ACK phase at time %t", $time);
       end

       last_ack = ack_got;  
       #(HIGH_PERIOD_SCL - 1);
       if (!last_ack) phase = M_ERROR;
    end
  endtask
  
  task readBit(output bit data);
    begin
       SCL_ctrl = 0;
       #LOW_PERIOD_SCL SCL_ctrl = 1;
       #1 data = SDA;
	   #(HIGH_PERIOD_SCL - 1); 	
    end
  endtask    

  task readData();
    begin
      // dodane
      phase = M_DATA_RX;
      // koniec dodanego

      for (i = 7; i >= 0; i--) begin
        // dodane
      	bit_idx = i;
        // koniec dodanego

      	readBit(data_got[i]);
      end

      // dodane
      bit_idx = BIT_ACK;
      ack_got = 0;
      // koniec dodanego
    end
  endtask
      
  task writeTransaction(input bit [6:0] addr, input bit [7:0] data); 
    begin
      // dodane
      phase    = M_IDLE;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b0);

      // dodane ack po adresie 
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        sendData(data);

        // (opcjonalnie) jeśli sprwadzamy ACK po danych
        // dodane
        getACK(1'b0);
        // koniec dodanego
      end

      sendStop();
    end
  endtask
  
  task writeTransactionReg(input bit [6:0] addr, input bit [7:0] bitister, input bit [7:0] data); 
    begin
      // dodane
      phase    = M_IDLE;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b0);

      // dodane ack po adresie 
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        sendData(bitister);

        // (opcjonalnie) jeśli sprwadzamy ACK po danych
        // dodane
        ack_got = 0;
        // koniec dodanego
      end
      
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        sendData(data);

        // (opcjonalnie) jeśli sprwadzamy ACK po danych
        // dodane
        getACK(1'b0);
        // koniec dodanego
      end

      sendStop();
    end
  endtask
  
  task readTransaction(input bit [6:0] addr); 
    begin
      // dodane
      phase    = M_IDLE;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b1);

      // dodane
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        readData();
      end

      // NACK po ostatnim bajcie read (master->target)
      // dodane
      phase   = M_ACK_DATA;
      bit_idx = BIT_ACK;
      // koniec dodanego

      sendBit(1'b1);
      sendStop();
    end
  endtask

  task burstRead(input bit [6:0] addr, input int numBytes); 
    begin
      // dodane
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b1);

      // dodane
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        for (i = numBytes; i > 0; i--) begin
          // dodane
          byte_idx = (numBytes - i);
          // koniec dodanego

          readData();
          if(i>1) begin
            // ACK po bajcie read (master potwierdza że chce kolejny)
            // dodane
            phase   = M_ACK_DATA;
            bit_idx = BIT_ACK;
            // koniec dodanego

            sendBit(1'b0);
          end
        end
      end

      // NACK po ostatnim bajcie
      // dodane ACK slot (master wysyła NACK=1)
      phase   = M_ACK_DATA;
      bit_idx = BIT_ACK;
      // koniec dodanego

      sendBit(1'b1);
      sendStop();
    end
  endtask

  task burstWrite(input bit [6:0] addr, input bit [7:0] data [$]);
    int numBytes;
    begin
      numBytes = data.size();
      // dodane
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // konied dodanego

      sendStart();
      sendAddressRW(addr, 1'b0);

      // dodane
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        foreach (data[j]) begin
            // dodane
            byte_idx = (numBytes-1 - j);
            // koniec dodanego

            sendData(data[j]);

            // dodane
            getACK(1'b0);
            // koniec dodanego
        end
      end
      sendStop();
    end
  endtask
  
  task writeRandomStop(input bit [6:0] addr, input bit [7:0] data, int randbit); 
    begin
      // dodane
      phase    = M_IDLE;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b0);

      // dodane ack po adresie 
      getACK(1'b1);
    	  // koniec dodanego
	phase = M_DATA_TX;
      if(ack_got) begin
        for (i = 7; i >= 7-randbit; i--) begin
          bit_idx  = i;
          sendBit(data[i]);
          
        end
        // (opcjonalnie) jeśli sprwadzamy ACK po danych
        // dodane
        // koniec dodanego
      end          
      sendStop();
    end
  endtask

task transactionDriver();
  begin
    Transaction tr;
    forever begin
      tr_mailbox.get(tr); // Wait for new transaction

      if(tr.rw == 0) begin // Write
        if (tr.data.size() == 1) begin
          writeTransaction(tr.address, tr.data.pop_front());
        end else if (tr.data.size() > 1) begin // Fixed logical comparison
          burstWrite(tr.address, tr.data);
        end
      end else begin // Read
        if(tr.readlen == 1) begin
          readTransaction(tr.address);
        end else if(tr.readlen > 1) begin
          burstRead(tr.address, tr.readlen);
        end
      end
    end
  end
  endtask

endmodule



//I2C Target - Standard I2C protocol (fSCL up to 100kHz)
module target_I2C(rst,clk,data_send,SDA_bidir,SCL_bidir,data_received);

//Parameter declarations
localparam IDLE=0;                                      //IDLE state
localparam BIT_CYCLE_LOW_ADDR=1;                        //SCL LOW period for the address RX
localparam BIT_CYCLE_HIGH_ADDR=2;                       //SCL HIGH period for the address RX
localparam BIT_CYCLE_LOW_ADDR_ACK=3;                    //SCL LOW period for the ack TX
localparam BIT_CYCLE_HIGH_ADDR_ACK=4;                   //SCL HIGH period for the ack TX
localparam CLOCK_STRETCHING = 5;                        //Clock strecthing (byte level clock streching option)
localparam BIT_CYCLE_LOW_DATA=6;                        //LOW period for data TX/RX
localparam BIT_CYCLE_HIGH_DATA=7;                       //HIGH period for data TX/RX
localparam BIT_CYCLE_LOW_DATA_ACK=8;                    //LOW period for ack bit TX/RX
localparam BIT_CYCLE_HIGH_DATA_ACK=9;                   //HIGH period for ack bit RX/TX
localparam HALT=10;                                     //HALT state
//Timing parameters
parameter THD_STA=225;                                  //Hold time for START condition. 4.5usec at 50MHZ clock (from spec: minimum of 4us)
parameter SDA_UPDATE=50;                                //Target SDA update instance after positive edge of SCL
parameter TSU_DAT=100;                                  //Data setup time. 2us at 50MHz clock (from spec: minimum of 250ns)
parameter TSU_STO=225;                                  //Set-up time for STOP condition 4.5us at 50MHz (from spec: minimum of 4us)
parameter THIGH_SAMPLE=50;                              //Sampling instance of the SDA line after positive edge of SCL. 1us at 50MHz clock

//Application parameters
parameter BYTES_SEND = 2;                               //Number of bytes to be sent (target-->controller)
parameter BITS_SEND=BYTES_SEND<<3;                      //Calculation of number of bit to be sent
parameter BYTES_RECEIVE=2;                              //Number of bytes to be received (controller-->target)
parameter BITS_RECEIVE=BYTES_RECEIVE<<3;                //Calculation of number of bits to be received
parameter ADDR_TARGET=7'b0000111;                       //Target address
parameter STRETCH = 0;//1000 0 tez dziala            //Number of clock cycles for clock-stretching after each address\data byte 

//Input Deceleration
input logic rst;                                     //Active high logic
input logic clk;                                        //target's internal clock (50MHz)
input logic [BITS_SEND-1:0] data_send;                  //Data to be sent to the controller (R/W='0')

//Output deleration
output logic [BITS_RECEIVE-1:0] data_received;          //Data received from the controller (R/W='1')

//Bidirectional signals
inout SDA_bidir;                                        //Serial data
inout SCL_bidir;                                        //Serial clock

//internal logic signals decelerations
logic SCL_tx;                                           //Tri-state logic - SCL output signal
logic SCL_rx;                                           //Tri-state logic - SCL input signal
logic SDA_tx;                                           //Tri-state logic - SDA output signal
logic SDA_rx;                                           //Tri-state logic - SDA input signal

logic [1:0] busy_state;                                 //Calculation of the bus status - FSM states
logic [1:0] next_busy_state;                            //Calculation of the bus status - FSM states
logic busy;                                             //Bus state (logic high if 'busy')

logic [4:0] state;                                      //Main FSM current state
logic [4:0] next_state;                                 //Main FSM next state

logic [9:0] count_low;                                  //Counts the Low period of the SCL signal
logic [9:0] count_high;                                 //Counts the High period of the SCL signal

logic [7:0] addr_received;                              //The first 8-bit frame sent by the controller
logic [BITS_SEND-1:0] data_send_sampled;                //Sampled 'data_send'

logic [3:0] count_addr;                                 //counts until 8 
logic [3:0] count_data;                                 //counts until 8
logic [9:0] count_stretch;                              //Maximum clock strecth period of 255 clock cycles (can also be declared as parameter if needed)
logic [BYTES_SEND-1:0] count_bytes_send;                //Counts the number of sent bytes (multiple bytes can be sent in a single iteration)
logic [BYTES_RECEIVE-1:0] count_bytes_received;         //Counts the number of received bytes (multiple bytes can ne received in a single iteration)

logic rw;                                               //The LSB of the address frame ('0' for TX and '1' for RX)
logic ack;                                              //Acknoledgement bit

logic [7:0] bit_mem [0:3]; // 4 bitisters: 0x00, 0x01, 0x02, 0x03
logic [7:0] bit_ptr;
logic [7:0] temp_byte;  
//HDL code  
//Bus state detection logic (i.e. free/busy)
always @(*)
  case (busy_state)
    2'b00: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b01 : 2'b00;
    2'b01: next_busy_state = ((SCL_rx==1'b0)&&(SDA_rx==1'b0)) ? 2'b10 : ((SCL_rx==1'b1)&&(SDA_rx==1'b1)) ? 2'b00 : 2'b01;	
    2'b10: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b11 : 2'b10;
    2'b11: next_busy_state = ((SCL_rx==1'b1)&&(SDA_rx==1'b1)) ? 2'b00 : (( SCL_rx==1'b1)&&(SDA_rx==1'b0)) ? 2'b11 : 2'b10;
  endcase

always @(posedge clk or negedge rst)	
  if (!rst)
    busy_state<=2'b00;
  else
    busy_state<=next_busy_state;

assign busy = ((busy_state==2'b10)||(busy_state==2'b11));

//FSM next state logic
always @(*)
case (state)
//During termination sequence carried by the controller the 'busy' signal is still high - initiate iteration only if the 'bytes' counters equal zero
IDLE: next_state= busy&&(count_bytes_received=='0)&&(count_bytes_send=='0) ? BIT_CYCLE_LOW_ADDR : IDLE; //TRY WITHOUT THIS LINE

//Receiving address frame
BIT_CYCLE_LOW_ADDR: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR : BIT_CYCLE_HIGH_ADDR;

BIT_CYCLE_HIGH_ADDR: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR : (count_addr<4'd8) ? BIT_CYCLE_LOW_ADDR : BIT_CYCLE_LOW_ADDR_ACK; 

//Respond with ACK bit if received address matches the target's address
BIT_CYCLE_LOW_ADDR_ACK: next_state = (addr_received[7:1]!=ADDR_TARGET) ? HALT : (SCL_rx==1'b0) ? BIT_CYCLE_LOW_ADDR_ACK : BIT_CYCLE_HIGH_ADDR_ACK;

BIT_CYCLE_HIGH_ADDR_ACK: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_ADDR_ACK : CLOCK_STRETCHING;		

//Clock strecthing (only for receiving data - remove the ~rw condition to implement for both TX and RX)
CLOCK_STRETCHING : next_state = (count_stretch<STRETCH)&&(~rw) ? CLOCK_STRETCHING: BIT_CYCLE_LOW_DATA;

//Sent or received data frame
BIT_CYCLE_LOW_DATA: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_HIGH_DATA;

BIT_CYCLE_HIGH_DATA: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA : (count_data<4'd8) ? BIT_CYCLE_LOW_DATA : BIT_CYCLE_LOW_DATA_ACK;		

//ACK/NACK bit
BIT_CYCLE_LOW_DATA_ACK: next_state = (SCL_rx==1'b0) ? BIT_CYCLE_LOW_DATA_ACK : BIT_CYCLE_HIGH_DATA_ACK;

BIT_CYCLE_HIGH_DATA_ACK: next_state = (SCL_rx==1'b1) ? BIT_CYCLE_HIGH_DATA_ACK : (ack==1'b1)&&(rw==1'b1) ? HALT :((count_bytes_received!=BYTES_RECEIVE)&&(rw==1'b0)) ? CLOCK_STRETCHING : ((count_bytes_send!=BYTES_SEND)&&(rw==1'b1)) ? CLOCK_STRETCHING : IDLE;

//HALT state - enter if the received address does not match
HALT: next_state = (~busy) ? IDLE : HALT;

default: next_state=IDLE;

endcase

//Calculate FSM next state
always @(posedge clk or negedge rst)
  if (!rst)
    state<=IDLE;
  else if (!busy && state != IDLE)
    state <= IDLE;
  else
  state<=next_state;

//Main I2C protocol logic
always @(posedge clk or negedge rst)
  if (!rst) begin
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
    count_stretch<='0;
	 data_received<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
    bit_mem[0] <= 8'hAA; // Default value for bit 0
    bit_mem[1] <= 8'hBB; // Default value for bit 1
    bit_mem[2] <= 8'hCC; // Default value for bit 2
    bit_mem[3] <= 8'hDD; // Default value for bit 3
    bit_ptr    <= 8'h00;
  end

  //Idle state
  else if (state==IDLE) begin
    if (busy==1'b0) begin
    count_low<='0;
    count_high<='0;
    count_addr<='0;
    count_data<='0;
    count_bytes_send<='0;
    count_bytes_received<='0;
    count_stretch<='0;
	 data_received<='0;
    SCL_tx<=1'b1;
    SDA_tx<=1'b1;
  end
  else begin                                      //Do no interfere with the termination sequence carried by the controller
    SDA_tx<=1'b1;	
    SCL_tx<=1'b1;
  end
  end

  //Receive 7-bit address + R/W bit
  else if (state==BIT_CYCLE_LOW_ADDR)
    count_high<='0;                               //Reset High period counter

  else if (state==BIT_CYCLE_HIGH_ADDR) begin
    data_send_sampled <= bit_mem[bit_ptr[1:0]]; //Data to be sent if the controller asks for data from the target
    count_high<=count_high+$bits(count_low)'(1);

  if (count_high==THIGH_SAMPLE) begin
    addr_received<={addr_received[6:0],SDA_rx};
    count_addr<=count_addr+$bits(count_addr)'(1);
  end
  count_low<='0;                                  //Reset LOW period counter
  end

  //Send acknoledgement bit for the address frame if the address matches the target's address
  else if (state==BIT_CYCLE_LOW_ADDR_ACK) begin
    count_low<=count_low+$bits(count_low)'(1);
    if ((count_low==SDA_UPDATE)&&(addr_received[7:1]==ADDR_TARGET)) 
      SDA_tx<=1'b0;
  count_high<='0;                                //Reset HIGH period counter
  end

  else if (state==BIT_CYCLE_HIGH_ADDR_ACK)       //During this period the controller sampled the ack bit
    count_low<='0;

  else if (state==CLOCK_STRETCHING) begin
    SCL_tx<=1'b0;
    SDA_tx<=1'b1;
    count_stretch<=count_stretch+$bits(count_stretch)'(1);
  end

  //Send or receive an 8-bit data frame
  else if (state==BIT_CYCLE_LOW_DATA) begin
    count_low<=count_low+$bits(count_low)'(1);
    SCL_tx<=1'b1;                                //Give back control of the SCL line to the controller after clock stretching period

  if ((count_low==SDA_UPDATE)&&(rw==1'b1)) begin
    SDA_tx<=data_send_sampled[BITS_SEND-1];
    data_send_sampled<=data_send_sampled<<1;			
    count_data<=count_data+$bits(count_data)'(1);
  end
  else if (rw==1'b0)
    SDA_tx<=1'b1;
  count_high<='0;                                //Reset HIGH period counter
  end

else if (state==BIT_CYCLE_HIGH_DATA) begin
    count_high <= count_high + $bits(count_low)'(1);

    if ((count_high==THIGH_SAMPLE) && (rw==1'b0)) begin
        
        // --- FIXED: Calculated the byte using the variable declared at top ---
        temp_byte = {data_received[BITS_RECEIVE-2:0], SDA_rx}; 
        
        data_received <= temp_byte; // Update the output buffer

        // Logic to distinguish Pointer vs Data
        if (count_bytes_received == 0) begin
            // 1st Byte received: This is the bitister Address (Pointer)
            bit_ptr <= temp_byte; 
        end
        else begin
            // 2nd+ Byte received: Write data to the bitister at bit_ptr
            bit_mem[bit_ptr[1:0]] <= temp_byte;
            
            // Optional: Auto-increment pointer if you want support for that
            // bit_ptr <= bit_ptr + 1; 
        end
        // -----------------------------------------------------------

        count_data <= count_data + $bits(count_data)'(1);
    end
    count_low <= '0; 
end

  //Send or receive acknoledgement bit for the data frame
  else if (state==BIT_CYCLE_LOW_DATA_ACK) begin
    count_low<=count_low+$bits(count_low)'(1);
    
  if (count_low == 0)
    SDA_tx <= 1'b1;
  if ((count_low<SDA_UPDATE) && (rw==1'b0)) 
    SDA_tx<=1'b1;
  if ((count_low==SDA_UPDATE)&&(rw==1'b0)) begin
    count_bytes_received<=count_bytes_received+$bits(count_bytes_received)'(1);
    SDA_tx<=1'b0;                               //send acknoledgement bit
  end
    count_high<='0;                             //Reset HIGH period counter
    count_stretch<='0;                          //Reset clock strectching counter
  end

  else if (state==BIT_CYCLE_HIGH_DATA_ACK) begin
    count_high<=count_high+$bits(count_low)'(1);
    count_low<='0;
    if ((count_high==THIGH_SAMPLE)&&(rw==1'b1)) begin
      ack<=SDA_rx;                               //Sample acknoledge bit sent by the controller
      count_bytes_send<=count_bytes_send+$bits(count_bytes_send)'(1);
      count_data<='0;                            //Reset the bit counter (indicates a byte has been sent/received)
    end
    else if (count_high==THIGH_SAMPLE) begin
      count_data<='0;                            //Reset the bit counter (indicates a byte has been sent/received)
      count_bytes_send<=count_bytes_send+$bits(count_bytes_send)'(1);
    end

  else if (state==HALT) begin
    SDA_tx=1'b1;
    SCL_tx=1'b1;
  end

end

assign rw = addr_received[0];
//Assign SDA_tx and SCL_tx values
assign SDA_bidir = SDA_tx ? 1'bz : 1'b0;
assign SDA_rx = SDA_bidir;

assign SCL_bidir = SCL_tx ? 1'bz : 1'b0;
assign SCL_rx=SCL_bidir; 

endmodule
