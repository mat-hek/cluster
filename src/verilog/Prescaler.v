module prescaler(
	input clkin,
	output reg clkout
);

parameter f = 28636360 / 8;

reg [24:0] cntr;
always@(posedge clkin) begin
	if(cntr < 28636360)
		cntr <= cntr + 1;
	else begin
		cntr <= 0;
		clkout <= ~clkout;
	end
end


endmodule
