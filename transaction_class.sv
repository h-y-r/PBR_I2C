package transaction_class;
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
endpackage
