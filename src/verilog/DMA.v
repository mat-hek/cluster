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
	input [1:0] action [0:PROC_CNT-1],
	input [SIZE-1:0] ptr [0:PROC_CNT-1],
	input [PROCSIZE-1:0] copy_start [0:PROC_CNT-1],
	input [PROCSIZE-1:0] copy_length [0:PROC_CNT-1],
	output [`PAGES_COUNT-1:0] ptr_out [0:PROC_CNT-1],
	output proc_mem_rw [0:PROC_CNT-1],
	output [WORD_SIZE-1:0] proc_mem_data_in [0:PROC_CNT-1],
	input [WORD_SIZE-1:0] proc_mem_data_out [0:PROC_CNT-1],
	output [PROCSIZE-1:0] proc_mem_addr [0:PROC_CNT-1],
	output [17:0] oLEDR,
	output [7:0] oLEDG,
	input [17:0] iSW,
	output [15:0] oDISP [0:2]
);

assign oDISP[2] = first_page;

assign oLEDR[17:14] = proc_mem_addr[current_proc];
assign oLEDR[13:10] = cn_addr;
assign oLEDG[5] = start;

// actions
`define READ 0
`define WRITE 1
`define FREE 2


// pages list

logic [`PAGES_COUNT-1:0] pl_addr;
logic [`PAGES_COUNT-1:0] pl_data_in;
logic pl_rw;
logic [`PAGES_COUNT-1:0] pl_data_out;


SHM_pages_list #(`PAGES_COUNT, PAGE_SIZE) pages_list(
	.address_a(pl_addr),
	.address_b(iSW[8:7]),
	.clock(mem_clock),
	.data_a(pl_data_in),
	.data_b(),
	.wren_a(pl_rw),
	.wren_b(0),
	.q_a(pl_data_out),
	.q_b(oDISP[0])
);

//alloc end pointers

logic [`PAGES_COUNT-1:0] aep_addr;
logic [`PAGES_COUNT-1:0] aep_addr2;
logic [`PAGES_COUNT-1:0] aep_data_in;
logic [`PAGES_COUNT-1:0] aep_data_in2;
logic aep_rw;
logic aep_rw2;
logic [`PAGES_COUNT-1:0] aep_data_out;
logic [`PAGES_COUNT-1:0] aep_data_out2;

SHM_alloc_end_ptrs #(`PAGES_COUNT, PAGE_SIZE) alloc_end_ptrs(
	.address_a(aep_addr),
	.address_b(iSW[6:5]),
	.clock(mem_clock),
	.data_a(aep_data_in),
	.data_b(),
	.wren_a(aep_rw),
	.wren_b(0),
	.q_a(aep_data_out),
	.q_b(oDISP[1])
);


// content

logic [SIZE-1:0] cn_addr;
logic [WORD_SIZE-1:0] cn_data_in;
logic cn_rw;
logic [WORD_SIZE-1:0] cn_data_out;

logic [3:0] cn_dbg_data_out;
assign oLEDR[3:0] = iSW[4] ? 4'b0 : cn_dbg_data_out;

SHM_content #(SIZE, WORD_SIZE) content(
	.address_a(cn_addr),
	.address_b(iSW[3:0]),
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

logic [2:0] stage;
`define LISTEN 0
`define STORE 1
`define LOAD 2
`define WAIT 3

logic [1:0] wait_next_stage;
logic [2:0] wait_time;

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

logic [PAGE_SIZE-1:0] last_page;
logic [1:0] update_last_page;
logic [PAGE_SIZE-1:0] first_page;
logic [1:0] update_first_page;
logic [SIZE-1:0] already_read;
task next_shm_addr(input ufp);
	begin
		if (cn_addr % PAGE_SIZE**2 == PAGE_SIZE**2-1) begin // last word of page
			cn_addr <= pl_data_out << PAGE_SIZE;
			pl_addr <= pl_data_out;
			pl_rw <= `READ;
			if(ufp)
				update_first_page <= 1;
		end else
			cn_addr <= cn_addr + 1;
	end
endtask

logic copying;

always@(current_proc, copying) if(copying) begin
	cn_data_in <= proc_mem_data_out[current_proc];
	proc_mem_data_in[current_proc] <= cn_data_out;
end

always@(posedge clock) begin
	if (start) begin
		stage <= `LISTEN;
		first_page <= 1;
		last_page <= `PAGES_COUNT-1;
		copying <= 0;
		run <= 1;
	end else if (run) begin
		case(update_last_page)
			1, 2: begin
				update_last_page <= update_last_page + 1;
				end
			3: begin
				update_last_page <= 0;
				last_page <= aep_data_out;
			end
		endcase
		case(update_first_page)
			1, 2: begin
				update_first_page <= update_first_page + 1;
				end
			3: begin
				update_first_page <= 0;
				first_page <= pl_data_out;
			end
		endcase
		case(stage)
			`LISTEN: begin
				if(last_trigger[current_proc] ^ trigger[current_proc]) begin
					case (action[current_proc])
						`WRITE: if(update_first_page == 0) begin
							last_trigger[current_proc] <= trigger[current_proc];
							proc_mem_rw[current_proc] <= `READ;
							proc_mem_addr[current_proc] <= copy_start[current_proc];
							if (ptr[current_proc] < 2**PAGE_SIZE) begin
								cn_addr <= first_page << PAGE_SIZE;
								pl_addr <= first_page;
								update_first_page <= 1;
							end else begin
								cn_addr <= ptr[current_proc];
								pl_addr <= ptr[current_proc] >> PAGE_SIZE;
							end
							stage <= `STORE;
						end
						`READ: begin
							last_trigger[current_proc] <= trigger[current_proc];
							cn_rw <= `READ;
							cn_addr <= ptr[current_proc];
							pl_rw <= `READ;
							pl_addr <= ptr[current_proc] >> PAGE_SIZE;
							if (ptr[current_proc] % PAGE_SIZE**2 >= PAGE_SIZE**2-2) begin
								wait_time <= PAGE_SIZE**2 - ptr[current_proc] % PAGE_SIZE**2;
								wait_next_stage <= `LOAD;
								stage <= `WAIT;
							end else
								stage <= `LOAD;
						end
						`FREE: begin							
							last_trigger[current_proc] <= trigger[current_proc];
							aep_rw <= `READ;
							aep_addr <= ptr[current_proc] >> PAGE_SIZE;
							pl_rw <= `WRITE;
							pl_addr <= last_page;
							pl_data_in <= ptr[current_proc] >> PAGE_SIZE;
							update_last_page <= 1;
							stage <= `LISTEN;
							//move_to_next_proc
						end
					endcase
					already_read <= 0;
				end //else
					//move_to_next_proc();
			end
			`WAIT: begin
				wait_time <= wait_time - 1;
				if (wait_time <= 0)
					stage <= wait_next_stage;
			end
			`LOAD: begin
				if (already_read < copy_length[current_proc]) begin
					next_shm_addr(0);
				end
				if (already_read < copy_length[current_proc] + 2) begin
					if (already_read == 1) begin					
						copying <= 1;
						proc_mem_rw[current_proc] <= `WRITE;
						proc_mem_addr[current_proc] <= copy_start[current_proc];
					end
					if (already_read > 1) begin
						proc_mem_addr[current_proc] <= proc_mem_addr[current_proc] + 1;
					end
					already_read <= already_read + 1;
				end else begin
					copying <= 0;
					proc_mem_rw[current_proc] <= `READ;
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
						copying <= 1;
						cn_rw <= `WRITE;
						pl_rw <= `READ;
					end
					if (already_read > 1) begin
						next_shm_addr(ptr[current_proc] < 2**PAGE_SIZE);
					end
					already_read <= already_read + 1;
				end else begin
					copying <= 0;
					cn_rw <= `READ;
					stage <= `LISTEN;
					if (ptr[current_proc] < 2**PAGE_SIZE) begin
						aep_addr <= ptr[current_proc] >> PAGE_SIZE;
						aep_data_in <= cn_addr >> PAGE_SIZE;
						aep_rw <= `WRITE;
					end
					//move_to_next_proc
				end
			end
		endcase
	end
end

endmodule
