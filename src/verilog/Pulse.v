module Pulse(
	input pclk,
	input clock,
	output pulse
);


logic last_pclk;
assign pulse = last_pclk ^ pclk;

always@(posedge clock) begin
	last_pclk <= pclk;
end

endmodule
