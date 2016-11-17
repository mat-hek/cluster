module processor (
	input proc_clock,
	input mem_clock,
	input START,
	input [7:0] MEM_DBG_ADDRESS,
	output [7:0] MEM_DBG_OUT,
	input [7:0] STACK_DBG_ADDRESS,
	output [7:0] STACK_DBG_OUT,
	input [7:0] CODE_DBG_ADDRESS,
	output [15:0] CODE_DBG_OUT,
	output reg [7:0] 	REGS [0:7]
);

`define HLT 		4'b0000
`define JXX 		4'b0001
	`define JZ  	4'b0000
	`define JNZ 	4'b0001
	`define JG  	4'b0010
	`define JGE 	4'b0011
	`define JL  	4'b0100
	`define JLE 	4'b0101
	`define JC  	4'b0110
	`define JNC 	4'b0111
	`define JO  	4'b1000
	`define JNO 	4'b1001
	`define JN  	4'b1010
	`define JNN 	4'b1011
	`define JMP 	4'b1100
`define AND 		4'b0010
`define OR  		4'b0011
`define XOR			4'b0100
`define NXX 		4'b0101
	`define NOT 	1'b0
	`define NEG 	1'b1
`define ADD 		4'b0110
`define SUB 		4'b0111
`define CMP 		4'b1000
`define TEST 		4'b1001
`define LEA 		4'b1010
`define SHX 		4'b1011
	`define SHR 	1'b0
	`define SHL 	1'b1
`define MOV 		4'b1100
`define PXX 		4'b1101
	`define PUSH    3'b000
	`define POP     3'b000
	`define PUSHF   3'b100
	`define POPF    3'b100
	`define PUSHIP  3'b010
	`define POPIP   3'b010
`define NOP 		4'b1110

`define OPCODE 		IR[15:12]
`define TYPE   		IR[11]
`define REG_A  		IR[10:8]
`define COND 		IR[11:8]
`define NUM    		IR[7:0]
`define REG_B  		IR[7:5]
`define REG_C  		IR[4:2]

`define REG_REG 	3'b000
`define MEM_REG 	3'b001
`define REG_MEM 	3'b010


logic [7:0] 	REG;

logic O;		// overflow flag
logic C;		// carry flag
logic Z;		// zero flag
logic N;		// negative/sign flag


logic [15:0] IR; 	// instruction register

logic  [7:0]	 IP;					// instruction pointer

logic [15:0]  CODE_DATA_OUT;
logic [15:0]  CODE_IN;
logic		 CODE_READ;

logic [15:0]  CODE_OUT;

assign CODE_IN = 0;
assign CODE_READ = 0;

code_seg CODE
(
	.address_a(IP),
	.address_b(CODE_DBG_ADDRESS),
	.clock(mem_clock),
	.data_a(CODE_IN),
	.data_b(CODE_IN),
	.wren_a(CODE_READ),
	.wren_b(CODE_READ),
	.q_a(CODE_DATA_OUT),
	.q_b(CODE_DBG_OUT)
);

logic  [7:0]	SP;				// stack pointer
logic  [7:0]  STACK_DATA_IN;
logic [7:0]  STACK_DATA_OUT;
logic 		STACK_WRITE;

logic [7:0]  STACK_IN;
logic [7:0]  STACK_OUT;
logic		STACK_READ;

assign STACK_READ = 0;
assign STACK_IN = 0;

stack_seg STACK
(
	.address_a(SP),
	.address_b(STACK_DBG_ADDRESS),
	.clock(mem_clock),
	.data_a(STACK_DATA_IN),
	.data_b(STACK_IN),
	.wren_a(STACK_WRITE),
	.wren_b(STACK_READ),
	.q_a(STACK_DATA_OUT),
	.q_b(STACK_DBG_OUT)
);


logic  [7:0]	MP;				// memory pointer
logic  [7:0]  MEM_DATA_IN;
logic [7:0]  MEM_DATA_OUT;
logic 		MEM_WRITE;

logic [7:0]  MEM_IN;
logic [7:0]  MEM_OUT;
logic		MEM_READ;

assign MEM_READ = 0;
assign MEM_IN = 0;

data_seg DATA
(
	.address_a(MP),
	.address_b(MEM_DBG_ADDRESS),
	.clock(mem_clock),
	.data_a(MEM_DATA_IN),
	.data_b(MEM_IN),
	.wren_a(MEM_WRITE),
	.wren_b(MEM_READ),
	.q_a(MEM_DATA_OUT),
	.q_b(MEM_DBG_OUT)
);


logic [7:0] reg1;
logic [7:0] reg2;
logic [7:0] result;
logic jump;

logic [1:0] STAGE;
logic RUN;

//=============================================================================
// Structural coding
//=============================================================================

always@(posedge proc_clock, negedge START) begin
	if(START == 0) begin
		RUN <= 1;
		STAGE <= 0;
		SP <= 0;
		IP <= 0;
		O <= 0;
		C <= 0;
		Z <= 0;
		N <= 0;
	end
	else begin
		if(RUN == 1) begin
			if(STAGE == 2'b00) begin
				IR <= CODE_DATA_OUT;
				IP <= IP + 1;
				STAGE <= STAGE + 1;
			end
			else begin
				case(`OPCODE)

					`HLT: begin
						RUN <= 0;
						STAGE <= 0;
					end

					`JXX: begin
						case(STAGE)
							2'b01: begin
								case(`COND)
									`JMP: jump <= 1'b1;
									`JZ: jump <= Z;
									`JNZ: jump <= ~Z;
									`JG: jump <= ~Z & ((~N & ~O) | (N & O));
									`JGE: jump <= (~N & ~O) | (N & O);
									`JL: jump <= (N & ~O) | (~N & O);
									`JLE: jump <= Z | ((N & ~O) | (~N & O));
									`JC: jump <= C;
									`JNC: jump <= ~C;
									`JO: jump <= O;
									`JNO: jump <= ~O;
									`JN: jump <= N;
									`JNN: jump <= ~N;
								endcase
								STAGE <= STAGE + 1;
							end
							2'b10: begin
								if(jump == 1)
									IP <= `NUM;
								STAGE <= 0;
							end
						endcase
					end

					`AND: begin
						if(`TYPE == 1)
							REGS[`REG_A] <= REGS[`REG_A] & `NUM;
						else
							REGS[`REG_A] <= REGS[`REG_A] & REGS[`REG_B];
						STAGE <= 0;
					end

					`OR: begin
						if(`TYPE == 1)
							REGS[`REG_A] <= REGS[`REG_A] | `NUM;
						else
							REGS[`REG_A] <= REGS[`REG_A] | REGS[`REG_B];
						STAGE <= 0;
					end

					`XOR: begin
						if(`TYPE == 1)
							REGS[`REG_A] <= REGS[`REG_A] ^ `NUM;
						else
							REGS[`REG_A] <= REGS[`REG_A] ^ REGS[`REG_B];
						STAGE <= 0;
					end

					`NXX: begin
						if(`TYPE == `NOT)
							REGS[`REG_A] <= ~REGS[`REG_A];
						else
							REGS[`REG_A] <= 0 - REGS[`REG_A];
						STAGE <= 0;
					end

					`ADD: begin
						case(STAGE)
							2'b01: begin
								reg1 <= REGS[`REG_A];
								if(`TYPE == 1)
									reg2 <= `NUM;
								else
									reg2 <= REGS[`REG_B];
								STAGE <= STAGE + 1;
							end
							2'b10: begin
								{C, result} <= reg1 + reg2;
								STAGE <= STAGE + 1;
							end
							2'b11: begin
								REGS[`REG_A] <= result;
								Z <= ~|(result);
								N <= result[7];
								case({C, reg1[7], reg2[7]})
									3'b001: O <= 1;
									3'b110: O <= 1;
								endcase
								STAGE <= 0;
							end
						endcase
					end

					`SUB: begin
						case(STAGE)
							2'b01: begin
								reg1 <= REGS[`REG_A];
								if(`TYPE == 1)
									reg2 <= `NUM;
								else
									reg2 <= REGS[`REG_B];
								STAGE <= STAGE + 1;
							end
							2'b10: begin
								{C, result} <= reg1 - reg2;
								STAGE <= STAGE + 1;
							end
							2'b11: begin
								REGS[`REG_A] <= result;
								Z <= ~|(result);
								N <= result[7];
								case({C, reg1[7], reg2[7]})
									3'b011: O <= 1;
									3'b100: O <= 1;
								endcase
								STAGE <= 0;
							end
						endcase
					end

					`CMP: begin
						case(STAGE)
							2'b01: begin
								reg1 <= REGS[`REG_A];
								if(`TYPE == 1)
									reg2 <= `NUM;
								else
									reg2 <= REGS[`REG_B];
								STAGE <= STAGE + 1;
							end
							2'b10: begin
								{C, result} <= reg1 - reg2;
								STAGE <= STAGE + 1;
							end
							2'b11: begin
								Z <= ~|(result);
								N <= result[7];
								case({C, reg1[7], reg2[7]})
									3'b011: O <= 1;
									3'b100: O <= 1;
								endcase
								STAGE <= 0;
							end
						endcase
					end

					`TEST: begin
						if(`TYPE == 1)
							Z <= ~|(REGS[`REG_A] & `NUM);
						else
							Z <= ~|(REGS[`REG_A] & REGS[`REG_B]);
						STAGE <= 0;
					end

					`LEA: begin
						REGS[`REG_A] <= `NUM;
						STAGE <= 0;
					end

					`SHX: begin
						if(`TYPE == `SHL)
							{C, REGS[`REG_A]} <= {C, REGS[`REG_A]} << `REG_B;
						else
							{REGS[`REG_A], C} <= {REGS[`REG_A], C} >> `REG_B;
						STAGE <= 0;
					end

					`MOV: begin
						if(`TYPE == 1) begin
							REGS[`REG_A] <= `NUM;
							STAGE <= 0;
						end
						else begin
							case(`REG_A)
								`REG_REG: begin
										REGS[`REG_B] <= REGS[`REG_C];
										STAGE <= 0;
								end
								`MEM_REG: begin
									case(STAGE)
										2'b01: begin
											MP <= REGS[`REG_B];
											MEM_DATA_IN <= REGS[`REG_C];
											STAGE <= STAGE + 1;
										end
										2'b10: begin
											MEM_WRITE <= 1;
											STAGE <= 0;
										end
									endcase
								end
								`REG_MEM: begin
									case(STAGE)
										2'b01: begin
											MEM_WRITE <= 0;
											MP <= REGS[`REG_C];
											STAGE <= STAGE + 1;
										end
										2'b10: begin
											REGS[`REG_B] <= MEM_DATA_OUT;
											STAGE <= 0;
										end
									endcase
								end
							endcase
						end
					end

					`PXX: begin
						if(`TYPE == 1) begin
							case(STAGE)
								2'b01: begin
									STACK_WRITE <= 1;
									STAGE <= STAGE + 1;
								end
								2'b10: begin
									case(`REG_A)
										`PUSH:
												STACK_DATA_IN <= REGS[`REG_B];
										`PUSHF:
												STACK_DATA_IN <= {1'b0, 1'b0, 1'b0, 1'b0, O, C, Z, N};
										`PUSHIP:
												STACK_DATA_IN <= IP + 1;
									endcase
									STAGE <= STAGE + 1;
								end
								2'b11: begin
									SP <= SP + 1;
									STAGE <= 0;
								end
							endcase
						end

						else begin
							case(STAGE)
								2'b01: begin
									STACK_WRITE <= 0;
									SP <= SP - 1;
									STAGE <= STAGE + 1;
								end
								2'b10: begin
									case(`REG_A)
										`POP:
												REGS[`REG_B] <= STACK_DATA_OUT;
										`POPF:
												{result[7:4], O, C, Z, N} <= STACK_DATA_OUT;
										`POPIP:
												IP <= STACK_DATA_OUT;
									endcase
									STAGE <= 0;
								end
							endcase
						end

					end

					`NOP: begin
						REGS[0] <= REGS[0];
						STAGE <= 0;
					end

				endcase
			end
		end
	end
end


endmodule
