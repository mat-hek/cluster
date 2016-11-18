module Dispatcher #(
	PROC_CNT
)(
	input start,
	input clock,
	input memory_clock,
	inout [7:0] proc_addr[0:PROC_CNT-1],
	inout proc_onspawn[0:PROC_CNT-1],
	inout [0:PROC_CNT-1] proc_start
);

logic [7:0] q_in;
logic [7:0] q_out;
logic q_dequeue;
logic q_enqueue;
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

logic [0:$clog2(PROC_CNT)-1] current_proc;
logic [0:$clog2(PROC_CNT)-1] free_proc_count;
logic onspawn_stage;
logic onready_stage;
logic run;

always@(posedge clock, posedge start) begin
	if(start == 1) begin
		current_proc <= 0;
		proc_addr[PROC_CNT-1] <= 0;
		proc_start <= 1;
		onspawn_stage <= 0;
		onready_stage <= 0;
		free_proc_count <= PROC_CNT-1;
		run <= 1;
	end else if (run) begin
		if (current_proc == 0) begin
			if (free_proc_count == PROC_CNT)
				run <= 0;
			free_proc_count <= 0;
		end
		if (onspawn_stage == 0 && onready_stage == 0) begin
			if (proc_onspawn[current_proc]) begin
				proc_onspawn[current_proc] <= 0;
				q_enqueue <= 1;
				q_in <= proc_addr[current_proc];
				onspawn_stage <= 1;
			end else if (!proc_start[current_proc]) begin
				if (!q_empty) begin
					q_dequeue <= 1;
					onready_stage <= 1;
				end else
					free_proc_count++;
			end else
				current_proc <= (current_proc + 1) % PROC_CNT;
		end
		if (onspawn_stage == 1) begin
			q_enqueue <= 0;
			onspawn_stage <= 0;
		end
		if (onready_stage == 1) begin
			proc_addr[current_proc] <= q_out;
			q_dequeue <=0;
			proc_start[current_proc] <= 1;
			onready_stage <= 0;
			current_proc <= (current_proc + 1) % PROC_CNT;
		end
	end
end

endmodule
