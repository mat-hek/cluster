module Dispatcher #(
	PROC_CNT
)(
	input start,
	input clock,
	input memory_clock,
	input proc_running[0:PROC_CNT-1],
	input [7:0] proc_spawn_addr[0:PROC_CNT-1],
	input proc_onspawn[0:PROC_CNT-1],
	output proc_ack[0:PROC_CNT-1],
	output [7:0] proc_start_addr[0:PROC_CNT-1],
	output proc_start[0:PROC_CNT-1],
	output dbg_1,
	output dbg_2,
	output dbg_3
);

logic last_proc_onspawn[0:PROC_CNT-1];

logic [7:0] q_in;
logic [7:0] q_out;
logic q_dequeue;
logic q_enqueue;
logic p_q_enqueue;
Pulse pm_q_enqueue(
	.clock(clock),
	.pclk(p_q_enqueue),
	.pulse(q_enqueue)
);
logic q_empty;
logic q_full; //TODO: throw exception on overflow

Dispatcher_queue q(
	.clock(memory_clock),
	.data(q_in),
	.rdreq(q_dequeue),
	.wrreq(q_enqueue),
	.empty(q_empty),
	.full(q_full),
	.q(q_out)
);

logic [0:1] current_proc;
logic [0:1] free_proc_count;
logic onready_stage;
logic run;
assign dbg_1 = run;
assign dbg_2 = start;
assign dbg_3 = current_proc;

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

always@(posedge clock) begin
	if(start == 1) begin
		current_proc <= 0;
		proc_start_addr[PROC_CNT-1] <= 0;
		proc_start[PROC_CNT-1] <= 1;
		onready_stage <= 0;
		free_proc_count <= PROC_CNT-1;
		run <= 1;
	end else if (run) begin
		proc_start[(PROC_CNT+current_proc-1)%PROC_CNT] <= 0;
		if (current_proc == 0) begin
			// if (free_proc_count == PROC_CNT)
				// run <= 0;
			free_proc_count <= 0;
		end
		if (onready_stage == 0) begin
			if (proc_onspawn[current_proc] ^ last_proc_onspawn[current_proc]) begin
				last_proc_onspawn[current_proc] <= proc_onspawn[current_proc];
				p_q_enqueue <= ~p_q_enqueue;
				q_in <= proc_spawn_addr[current_proc];
				proc_ack[current_proc] <= ~proc_ack[current_proc];
				moveToNextProc();
			end else if (!proc_running[current_proc]) begin
				if (!q_empty) begin
					q_dequeue <= 1;
					onready_stage <= 1;
				end else begin
					free_proc_count <= free_proc_count + 1;
					moveToNextProc();
				end
			end else
				moveToNextProc();
		end
		if (onready_stage == 1) begin
			proc_start_addr[current_proc] <= q_out;
			q_dequeue <= 0;
			proc_start[current_proc] <= 1;
			onready_stage <= 0;
			moveToNextProc();
		end
	end
end

endmodule
