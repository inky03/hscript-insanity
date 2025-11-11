package insanity;

import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

class Script {
	public var name:String;
	
	var parser:Parser = new Parser();
	var interp:Interp = new Interp();
	var program:Expr = null;
	
	public var variables(get, never):Map<String, Dynamic>;
	inline function get_variables():Map<String, Dynamic> { return interp.variables; }
	
	public function new(string:String, name:String = 'hscript'):Void {
		this.name = name;
		parser.allowTypes = true;
		
		parse(string);
	}
	
	public function parse(string:String):Expr {
		try {
			program = parser.parseString(string, name);
		} catch (e:haxe.Exception) {
			trace('Failed to initialize script program!\n' + e.details());
		}
		
		return program;
	}
	
	public function execute(?expr:Expr):Dynamic {
		try {
			if (program == null) throw 'Uninitialized';
			return interp.execute(program);
		} catch (e:haxe.Exception) {
			trace('Script program halted!\n' + e.details());
			// trace(Type.typeof(e));
			// trace('Failed to execute program: $e');
		}
		
		return null;
	}
	
	public function call(variable:String, ?args:Array<Dynamic>):Dynamic {
		var fun = variables.get(variable);
		
		if (!Reflect.isFunction(fun)) {
			trace('$variable isn\'t a function');
			return null;
		}
		
		try {
			return Reflect.callMethod(interp, fun, args ?? []);
		} catch (e:haxe.Exception) {
			trace('Error when calling function!\n' + e.details());
			return null;
		}
	}
}