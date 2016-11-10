parameter SIZE = 16;
parameter WORD_SIZE = 16;
parameter PAGE_SIZE = 4;
`define PAGES_COUNT (SIZE - PAGE_SIZE)

module SHM #(
	PROC_CNT
)(
	input clock,
	input [1:0] action [0:PROC_CNT-1],
	input [`PAGES_COUNT-1:0] ptr [0:PROC_CNT-1], 
	input [SIZE-1:0] shift [0:PROC_CNT-1],
	input [WORD_SIZE-1:0] data_in [0:PROC_CNT-1],
	output [WORD_SIZE-1:0] data_out [0:PROC_CNT-1],
	input [SIZE-1:0] cn_dbg_addr,
	output [WORD_SIZE-1:0] cn_dbg_data_out
);

// actions:
	`define READ 0
	`define WRITE 1
	`define ALLOC 2
	`define FREE 3


// pages list

logic [`PAGES_COUNT-1:0] pl_addr1;
logic [`PAGES_COUNT-1:0] pl_addr2;
logic [`PAGES_COUNT-1:0] pl_data_in1;
logic [`PAGES_COUNT-1:0] pl_data_in2;
logic pl_rw1;
logic pl_rw2;
logic [`PAGES_COUNT-1:0] pl_data_out1;
logic [`PAGES_COUNT-1:0] pl_data_out2;


SHM_pages_list pages_list(
	.address_a(pl_addr1),
	.address_b(pl_addr2),
	.clock(clock),
	.data_a(pl_data_in1),
	.data_b(pl_data_in2),
	.wren_a(pl_rw1),
	.wren_b(pl_rw2),
	.q_a(pl_data_out1),
	.q_b(pl_data_out2)
);

// content

logic [SIZE-1:0] cn_addr;
logic [WORD_SIZE-1:0] cn_data_in;
logic cn_rw;
logic [WORD_SIZE-1:0] cn_data_out;


SHM_content content(
	.address_a(cn_addr),
	.address_b(cn_dbg_addr),
	.clock(clock),
	.data_a(cn_data_in),
	.data_b(/*cn_dbg_data_in*/),
	.wren_a(cn_rw),
	.wren_b(/*cn_dbg_rw*/ 0),
	.q_a(cn_data_out),
	.q_b(cn_dbg_data_out)
);

endmodule
