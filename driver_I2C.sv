`timescale 1ns/10ps
import transaction_class::*;

 class I2C_Config;
   rand realtime high_period;
   rand realtime low_period;
   rand realtime setup_time;
   rand realtime start_setup_time;
   rand realtime start_hold_time;
   rand realtime stop_setup_time;
   rand realtime rand_bit;

   constraint i2c_time_const {
     //Min High: 4000ns, Min Low: 4700ns, Min Setup Time: 250ns 
     high_period inside {[4000:7000]}; 
     low_period  inside {[4700:7000]};
     setup_time  inside {[250:4700]};
     start_setup_time  inside {[4700:7000]};
     start_hold_time  inside {[4000:7000]};
     stop_setup_time  inside {[4000:7000]};
     rand_bit    inside {[0:7]};
   }
 endclass


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
    M_ERROR,      // blad nack po adresie czy cos
	M_ADDR_10BIT, //adresowanie 10 bit
	M_DEVICE_ID, //zbiera ID od slave'a
	M_SEND_ADDR_FOR_ID,
	M_SR
  } master_phase_e;

  master_phase_e phase = M_IDLE;

  typedef mailbox #(Transaction) tr_mbx;

  tr_mbx tr_mailbox;
 
  initial begin
    tr_mailbox = new();//mailbox na transakcje
    fork
      dv_i2c.transactionDriver();
    join_none
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

  task sendRepeatedStart();
    begin
      phase    = M_SR;
      bit_idx  = BIT_ACK;
      byte_idx = -1;

	  assert(SCL === 1'b0) 
	  	else $error("SCL musi być 0!");
	  SCL_ctrl = 1;		
	  #(START_SETUP_TIME);
      SDA_ctrl = 0;
	  #(START_HOLD_TIME);
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
	  data_got = 8'b0;	
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
      int k;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b1);

      // dodane
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        for (k = numBytes; k > 0; k--) begin
          // dodane
          byte_idx = (numBytes - k);
          // koniec dodanego

          readData();
          if(k>1) begin
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
	
task sendAdress10Bit(input bit [9:0] addr);
	bit [4:0] code = 5'b11110;
	phase = M_ADDR_10BIT;
	byte_idx = -1;
	sendStart();
	
	for (i = 4; i >= 0; i--) begin
          bit_idx  = i;
		  sendBit(code[i]);
	end
	
	sendBit(addr[9]);
	sendBit(addr[8]);
	bit_idx = BIT_RW;
	sendBit(1'b0);
	
	SDA_ctrl = 1;
    getACK(1'b1); 
    ack_got = 0;   
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(addr[i]);
    end

	SDA_ctrl = 1;
    getACK(1'b1); 		
endtask

task writeTransaction10BIT(input bit [9:0] addr, input bit [7:0] data);
	sendAdress10Bit(addr, 1'b0);
	
	if(ack_got) begin
	sendData(data);
	// (opcjonalnie) jeśli sprwadzamy ACK po danych
	getACK(1'b0);
	end

	sendStop();	
endtask

task readTransaction10BIT(input bit [9:0] addr);
	bit [4:0] code = 5'b11110;
	sendAdress10Bit(addr);
	sendRepeatedStart();
	
	for (i = 4; i >= 0; i--) begin
          bit_idx  = i;
		  sendBit(code[i]);
	end
	
	sendBit(addr[9]);
	sendBit(addr[8]);
	bit_idx = BIT_RW;
	sendBit(1'b1);
	SDA_ctrl = 1;
    getACK(1'b1); 
	
	if(ack_got) begin
		readData();
	end

	// NACK po ostatnim bajcie read (master->target)
	phase   = M_ACK_DATA;
	bit_idx = BIT_ACK;

	sendBit(1'b1);
	sendStop();
endtask


task getDeviceID(input bit [6:0] addr)
	bit [7:0] devID1 = 8'b11111000;
	bit [7:0] devID2 = 8'b11111001;
	phase = M_DEVICE_ID;	
	sendStart();
	
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(devID1[i]);
    end
	
    SDA_ctrl = 1;
	getACK(1'b1);
	
	phase = M_SEND_ADDR_FOR_ID;
	for (i = 6; i >= 0; i--) begin
        bit_idx = i;
        sendBit(addr[i]);
    end	
	sendBit(1'b1); //dont care bit
	
	SDA_ctrl = 1;
	getACK(1'b1);
	
	sendStart();
	
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(devID2[i]);
    end
	
	SDA_ctrl = 1;
	getACK(1'b1);
	
	if(ack_got) begin
	for (k = 3; k > 0; k--) begin
	  byte_idx = (numBytes - k);

	  readData();
	  if(k>1) begin
		// ACK po bajcie read (master potwierdza że chce kolejny)
		bit_idx = BIT_ACK;
		sendBit(1'b0);
	  end
	end
	end
	
	sendStop();
	
endtask
			
task transactionDriver();
  begin
    Transaction tr;
    forever begin
      tr_mailbox.get(tr);

      if(tr.rw == 0) begin // Write
        if (tr.data.size() == 1) begin
          writeTransaction(tr.address, tr.data.pop_front());
        end else if (tr.data.size() > 1) begin
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

endmodule`timescale 1ns/10ps
import transaction_class::*;

 class I2C_Config;
   rand realtime high_period;
   rand realtime low_period;
   rand realtime setup_time;
   rand realtime start_setup_time;
   rand realtime start_hold_time;
   rand realtime stop_setup_time;
   rand realtime rand_bit;

   constraint i2c_time_const {
     //Min High: 4000ns, Min Low: 4700ns, Min Setup Time: 250ns 
     high_period inside {[4000:7000]}; 
     low_period  inside {[4700:7000]};
     setup_time  inside {[250:4700]};
     start_setup_time  inside {[4700:7000]};
     start_hold_time  inside {[4000:7000]};
     stop_setup_time  inside {[4000:7000]};
     rand_bit    inside {[0:7]};
   }
 endclass


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
    M_ERROR,      // blad nack po adresie czy cos
	M_ADDR_10BIT, //adresowanie 10 bit
	M_DEVICE_ID, //zbiera ID od slave'a
	M_SEND_ADDR_FOR_ID  
  } master_phase_e;

  master_phase_e phase = M_IDLE;

  typedef mailbox #(Transaction) tr_mbx;

  tr_mbx tr_mailbox;
 
  initial begin
    tr_mailbox = new();//mailbox na transakcje
    fork
      dv_i2c.transactionDriver();
    join_none
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
	  data_got = 8'b0;	
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
      int k;
      byte_idx = -1;
      bit_idx  = BIT_ACK;
      // koniec dodanego

      sendStart();
      sendAddressRW(addr, 1'b1);

      // dodane
      getACK(1'b1);
      // koniec dodanego

      if(ack_got) begin
        for (k = numBytes; k > 0; k--) begin
          // dodane
          byte_idx = (numBytes - k);
          // koniec dodanego

          readData();
          if(k>1) begin
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
	
task sendAdress10Bit(input bit [9:0] addr, input bit rw);
	bit [4:0] code = 5'b11110;
	phase = M_ADDR_10BIT;
	byte_idx = -1;
	sendStart();
	
	for (i = 4; i >= 0; i--) begin
          bit_idx  = i;
		  sendBit(code[i]);
	end
	
	sendBit(addr[9]);
	sendBit(addr[8]);
	sendBit(rw);
	
	bit_idx = BIT_RW;
	SDA_ctrl = 1;
    getACK(1'b1);  
       
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(addr[i]);
    end

	bit_idx = BIT_RW;
	SDA_ctrl = 1;
    getACK(1'b1); 		
endtask

task getDeviceID(input bit [6:0] addr)
	bit [7:0] devID1 = 8'b11111000;
	bit [7:0] devID2 = 8'b11111001;
	phase = M_DEVICE_ID;	
	sendStart();
	
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(devID1[i]);
    end
	
	bit_idx = BIT_ACK;
    SDA_ctrl = 1;
	getACK(1'b1);
	
	phase = M_SEND_ADDR_FOR_ID;
	for (i = 6; i >= 0; i--) begin
        bit_idx = i;
        sendBit(addr[i]);
    end	
	sendBit(1'b1); //dont care bit
	
	bit_idx = BIT_ACK;
	SDA_ctrl = 1;
	getACK(1'b1);
	
	sendStart();
	
	for (i = 7; i >= 0; i--) begin
        bit_idx = i;
        sendBit(devID2[i]);
    end
	
	bit_idx = BIT_ACK;
	SDA_ctrl = 1;
	getACK(1'b1);
	
	if(ack_got) begin
	for (k = 3; k > 0; k--) begin
	  byte_idx = (numBytes - k);

	  readData();
	  if(k>1) begin
		// ACK po bajcie read (master potwierdza że chce kolejny)
		bit_idx = BIT_ACK;
		sendBit(1'b0);
	  end
	end
	end
	
	sendStop();
	
endtask
			
task transactionDriver();
  begin
    Transaction tr;
    forever begin
      tr_mailbox.get(tr);

      if(tr.rw == 0) begin // Write
        if (tr.data.size() == 1) begin
          writeTransaction(tr.address, tr.data.pop_front());
        end else if (tr.data.size() > 1) begin
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
