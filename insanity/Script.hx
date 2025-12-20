package insanity;

import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

class Script {
	public var name:String;
	
	var parser:Parser = new Parser();
	var interp:Interp = null;
	var program:Expr = null;
	
	public var variables(get, never):Map<String, Dynamic>;
	inline function get_variables():Map<String, Dynamic> { return interp.variables; }
	
	public function new(string:String, name:String = 'hscript', ?environment:Environment):Void {
		parser.allowTypes = parser.allowJSON = true;
		interp = new Interp(environment);
		
		this.name = name;
		
		parse(string);
	}
	
	public function parse(string:String):Expr {
		try {
			program = parser.parseScript(string, name);
		} catch (e:haxe.Exception) {
			onParsingError(e);
			program = null;
		}
		
		return program;
	}
	
	public function start(?expr:Expr):Any {
		try {
			if (program == null) throw 'Program is uninitialized';
			
			setDefaults();
			return interp.execute(program);
		} catch (e:haxe.Exception) {
			onProgramError(e);
		}
		
		return null;
	}
	
	public function call(variable:String, ...args:Any):Any {
		if (interp == null) throw 'Interpreter is uninitialized';
		
		var fun = variables.get(variable);
		
		if (!Reflect.isFunction(fun)) {
			trace('$variable isn\'t a function');
			return null;
		}
		
		return Reflect.callMethod(interp, fun, args.toArray());
	}
	
	public function setDefaults():Void {
		interp.setDefaults();
		
		interp.variables.set('this', this);
	}
	
	public dynamic function onParsingError(e:haxe.Exception):Void {
		trace('Failed to initialize script program!\n' + e.details());
	}
	public dynamic function onProgramError(e:haxe.Exception):Void {
		trace('Script program stopped unexpectedly!\n' + e.details());
	}
}