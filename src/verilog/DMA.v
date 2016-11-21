localparam PROCSIZE = 4;
localparam SIZE = 4;
localparam WORD_SIZE = 16;
localparam PAGE_SIZE = 2;
`define PAGES_COUNT (SIZE - PAGE_SIZE)

module DMA #(
	PROC_CNT
)(
	input clock,
	input mem_clock,
	input start,
	input trigger [0:PROC_CNT-1],
	output ack [0:PROC_CNT-1],
	input [SIZE-1:0] ptr [0:PROC_CNT-1],
	output [WORD_SIZE-1:0] proc_mem_data_in [0:PROC_CNT-1],
	input [WORD_SIZE-1:0] proc_mem_data_out [0:PROC_CNT-1],
	output [PROCSIZE-1:0] proc_mem_addr [0:PROC_CNT-1],
	input [PROCSIZE-1:0] copy_start [0:PROC_CNT-1],
	input [PROCSIZE-1:0] copy_length [0:PROC_CNT-1],
	output proc_mem_rw [0:PROC_CNT-1],
	output [`PAGES_COUNT-1:0] ptr_out [0:PROC_CNT-1],
	input [SIZE-1:0] cn_dbg_addr,
	output [WORD_SIZE-1:0] cn_dbg_data_out,
	input [`PAGES_COUNT-1:0] pl_dbg_addr,
	output [PAGE_SIZE-1:0] pl_dbg_data_out,
	output [15:0] dbg1,
	output [15:0] dbg2,
	output [15:0] dbg3,
	output [15:0] dbg4,
	output run_dbg
);

assign dbg1 = cn_addr;
assign dbg2 = proc_mem_addr[current_proc];
assign dbg3 = next_page;
assign dbg4 = pl_data_out;
assign run_dbg = start;

// actions
`define READ 0
`define WRITE 1


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
	.address_b(pl_dbg_addr),
	.clock(mem_clock),
	.data_a(pl_data_in),
	.data_b(/*pl_dbg_data_in*/),
	.wren_a(pl_rw),
	.wren_b(0 /*pl_dbg_rw*/),
	.q_a(pl_data_out),
	.q_b(pl_dbg_data_out)
);

// content

logic [SIZE-1:0] cn_addr;
logic [WORD_SIZE-1:0] cn_data_in;
logic cn_rw;
logic [WORD_SIZE-1:0] cn_data_out;


SHM_content content(
	.address_a(cn_addr),
	.address_b(cn_dbg_addr),
	.clock(mem_clock),
	.data_a(cn_data_in),
	.data_b(/*cn_dbg_data_in*/),
	.wren_a(cn_rw),
	.wren_b(/*cn_dbg_rw*/ 0),
	.q_a(cn_data_out),
	.q_b(cn_dbg_data_out)
);


logic [$clog2(PROC_CNT)-1:0] current_proc;
logic last_trigger [0:PROC_CNT-1];

logic [1:0] stage;
`define LISTEN 0
`define STORE 1
`define LOAD 2

logic run;


function next_proc_no;
	input curr_proc;
	begin
		next_proc_no = (curr_proc + 1) % PROC_CNT;
	end
endfunction
task move_to_next_proc;
	begin
		current_proc <= next_proc_no(current_proc);
	end
endtask

logic [PAGE_SIZE-1:0] next_page;
logic [1:0] update_next_page;
logic [SIZE-1:0] already_read;
task next_shm_addr;
	begin
		if (cn_addr % PAGE_SIZE**2 == PAGE_SIZE**2-1) begin // last word of page
			cn_addr <= pl_data_out << PAGE_SIZE;
			pl_addr <= pl_data_out;
			pl_rw <= `READ;
			update_next_page <= 1;
		end else
			cn_addr <= cn_addr + 1;
	end
endtask

logic writing_to_shm;

always@(current_proc, writing_to_shm) if(writing_to_shm) begin
	cn_data_in <= proc_mem_data_out[current_proc];
	proc_mem_data_in[current_proc] <= cn_data_out;
end

always@(posedge clock) begin
	if (start) begin
		stage <= `LISTEN;
		next_page <= 1;
		writing_to_shm <= 0;
		run <= 1;
	end else if (run) begin
		case(update_next_page)
			1, 2: begin
				update_next_page <= update_next_page + 1;
				end
			3: begin
				update_next_page <= 0;
				next_page <= pl_data_out;
			end
		endcase
		case(stage)
			`LISTEN: begin
				if(last_trigger[current_proc] ^ trigger[current_proc]) begin
					last_trigger[current_proc] = trigger[current_proc];
					case (action)
						`WRITE: begin
							proc_mem_rw[current_proc] <= `READ;
							proc_mem_addr[current_proc] <= copy_start[current_proc];
							stage <= `STORE;
						end
						`READ: begin
							cn_rw <= `READ;
							cn_addr <= ptr[current_proc];
							stage <= `LOAD;
						end
					endcase	
					already_read <= 0;
				end //else
					//move_to_next_proc();
			end
			`LOAD: begin
				if (already_read < copy_length[current_proc]) begin
					proc_mem_addr[current_proc] <= proc_mem_addr[current_proc] + 1;
				end
				if (already_read < copy_length[current_proc] + 2) begin
					if (already_read == 1) begin					
						writing_to_shm <= 1;
						cn_rw <= `WRITE;
						cn_addr <= next_page << PAGE_SIZE;
						pl_addr <= next_page;
						pl_rw <= `READ;
						update_next_page <= 1;
					end
					if (already_read > 1) begin
						next_shm_addr();
					end
					already_read <= already_read + 1;
				end else begin
					writing_to_shm <= 0;
					cn_rw <= `READ;
					stage <= `LISTEN;
					//move_to_next_proc
				end
			end
			`STORE: begin
				if (already_read < copy_length[current_proc]) begin
					proc_mem_addr[current_proc] <= proc_mem_addr[current_proc] + 1;
				end
				if (already_read < copy_length[current_proc] + 2) begin
					if (already_read == 1) begin					
						writing_to_shm <= 1;
						cn_rw <= `WRITE;
						cn_addr <= next_page << PAGE_SIZE;
						pl_addr <= next_page;
						pl_rw <= `READ;
						update_next_page <= 1;
					end
					if (already_read > 1) begin
						next_shm_addr();
					end
					already_read <= already_read + 1;
				end else begin
					writing_to_shm <= 0;
					cn_rw <= `READ;
					stage <= `LISTEN;
					//move_to_next_proc
				end
			end
		endcase
	end
end

endmodule
