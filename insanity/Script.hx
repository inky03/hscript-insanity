package insanity;

import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

class Script {
	var parser:Parser = new Parser();
	var interp:Interp = new Interp();
	var program:Expr = null;
	
	public function new(string:String):Void {
		parser.allowTypes = true;
		
		execute(parse(string));
	}
	
	public function parse(string:String):Expr {
		try {
			program = parser.parseString(string);
		} catch (e:Error) {
			trace('Failed to create program: $e');
		}
		
		return program;
	}
	
	public function execute(?expr:Expr):Dynamic {
		try {
			if (program == null) throw 'Program is uninitialized';
			return interp.execute(program);
		} catch (e:Dynamic) {
			trace('Failed to execute program: $e');
		}
		
		return null;
	}
}