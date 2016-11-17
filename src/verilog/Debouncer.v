module debouncer(
	input button,
	input clk,
	output reg bt_act 		// button active
);
 
parameter TIME = 2863630;

reg [21:0] counter;

always@(posedge clk, negedge button) begin
	if(button == 0)
		counter <= 0;
	else if(counter < TIME) 
		counter <= counter + 1;
end

always@(posedge clk) begin
	if(counter < TIME)
		bt_act <= 0;
	else
		bt_act <= 1;
end

endmodule
