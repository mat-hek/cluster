parameter SIZE = 16;
parameter WORD_SIZE = 16;
parameter PAGE_SIZE = 4;
`define PAGES_COUNT (SIZE - PAGE_SIZE)

module SHM #(
	PROC_CNT
)(
	input clock,
	input start,
	input trigger [0:PROC_CNT-1],
	output ack [0:PROC_CNT-1],
	input [1:0] action [0:PROC_CNT-1],
	input [`PAGES_COUNT-1:0] ptr [0:PROC_CNT-1], 
	input [SIZE-1:0] shift [0:PROC_CNT-1],
	input [WORD_SIZE-1:0] data_in [0:PROC_CNT-1],
	output [WORD_SIZE-1:0] data_out [0:PROC_CNT-1],
	output [`PAGES_COUNT-1:0] ptr_out [0:PROC_CNT-1],
	input [SIZE-1:0] cn_dbg_addr,
	output [WORD_SIZE-1:0] cn_dbg_data_out
);


// pages list

logic [`PAGES_COUNT-1:0] pl_addr;
logic [`PAGES_COUNT-1:0] pl_addr2;
logic [`PAGES_COUNT-1:0] pl_data_in;
logic [`PAGES_COUNT-1:0] pl_data_in2;
logic pl_rw;
logic pl_rw2;
logic [`PAGES_COUNT-1:0] pl_data_out;
logic [`PAGES_COUNT-1:0] pl_data_out2;


SHM_pages_list pages_list(
	.address_a(pl_addr),
	.address_b(pl_addr2),
	.clock(clock),
	.data_a(pl_data_in),
	.data_b(pl_data_in2),
	.wren_a(pl_rw),
	.wren_b(pl_rw2),
	.q_a(pl_data_out),
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

// event handling

`define READ 0
`define WRITE 1
`define ALLOC 2
`define FREE 3


logic [$clog2(PROC_CNT)-1:0] current_proc;
logic last_trigger [0:PROC_CNT-1];

logic [`PAGES_COUNT-1:0] first_page;
logic update_first_page;

logic stage;
`define ADDR_UNRESOLVED 0
`define ADDR_RESOLVED 1

logic inner_stage;
logic run;

logic [`PAGES_COUNT-1:0] current_shift;
logic allocated_area_extended;

function nextProcNo;
	input curr_proc;
	begin
		nextProcNo = (curr_proc + 1) % PROC_CNT;
	end
endfunction
task moveToNextProc;
	begin
		current_proc <= nextProcNo(current_proc);
	end
endtask
task access_mem;
	input page;
	begin
		cn_addr <= page*PAGE_SIZE**2 + shift[current_proc] % PAGE_SIZE**2;
		cn_rw <= action[current_proc];
		ack[current_proc] <= ~ack[current_proc];
		case(action[current_proc])
			`READ: begin
			end
		
		endcase
	end
endtask

always@(posedge clock) begin
	if (start) begin
		stage <= `ADDR_UNRESOLVED;
		first_page <= 0;
		inner_stage <= 0;
		current_shift <= 0;
		allocated_area_extended <= 0;
		run <= 1;
	end else if (run) begin
		if (update_first_page) begin
			update_first_page <= 0;
			first_page <= pl_data_out;
		end
		case(stage)
			`ADDR_UNRESOLVED: begin
				if(last_trigger[current_proc] ^ trigger[current_proc]) begin
					case(action[current_proc])
						`READ, `WRITE: begin // resolve address
							case(inner_stage)
								0: begin
									if (shift[current_proc] < 2**PAGE_SIZE) begin // accessing first allocated page
										access_mem(ptr[current_proc]);
									end else begin // accessing further page
										current_shift <= 1;
										pl_addr <= ptr[current_proc];
										pl_rw <= `READ;
									end
								end
								1: begin
									if (shift[current_proc] < 2**PAGE_SIZE*current_shift) begin
										if (allocated_area_extended) begin
											allocated_area_extended <= 0;
											// mark allocation end (last_allocated_page.next = null)
											pl_addr <= pl_data_out;
											pl_data_in <= pl_data_out;
											pl_rw <= `WRITE;
											// update first_page (first_page = last_allocated_page.next)
											pl_addr2 <= pl_data_out;
											pl_rw2 <= `READ;
											update_first_page <= 1;
										end
										access_mem(pl_data_out);
										inner_stage <= 0;
									end else begin
										if (pl_addr == pl_data_out) begin // end of allocated area, extension necessary
											// next_page = first_free_page
											pl_addr <= first_page;
											// extend allocated area
											pl_addr2 <= pl_data_out;
											pl_data_in2 <= first_page;
											pl_rw2 <= `WRITE;
											allocated_area_extended <= 1;
										end else // move to the next page
											pl_addr <= pl_data_out;
									end
								end
							endcase
						end
						`ALLOC: begin
							// update output
							ptr_out[current_proc] <= first_page;
							ack[current_proc] <= ~ack[current_proc];
							// first_page.next = null
							pl_addr2 <= first_page;
							pl_data_in2 <= first_page;
							pl_rw2 <= `WRITE;
							// first_page = first_page.next
							pl_addr <= first_page;
							pl_rw <= `READ;
							update_first_page <= 1;
						end
						`FREE: begin
						
						end
									
					endcase
				end else
					moveToNextProc();
			end
			`ADDR_RESOLVED: begin
				
			end
		endcase
	end
end

endmodule
