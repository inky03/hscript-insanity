package insanity;

import insanity.backend.Exception;
import insanity.backend.Parser;
import insanity.backend.Interp;
import insanity.backend.Expr;

class Module {
	public var name:String;
	public var pack:Array<String>;
	
	var parser:Parser = new Parser();
	var interp:Interp = null;
	var types:Array<ModuleDecl> = [];
	
	public function new(string:String, name:String = 'hscript', ?pack:Array<String>):Void {
		parser.allowTypes = true;
		parser.allowJSON = true;
		
		this.name = name;
		this.pack = pack;
		
		parse(string);
	}
	
	public function parse(string:String):Array<ModuleDecl> {
		try {
			types = parser.parseModule(string, name, pack);
		} catch (e:haxe.Exception) {
			onParsingError(e);
			types.resize(0);
		}
		
		return types;
	}
	
	public dynamic function onParsingError(e:haxe.Exception):Void {
		trace('Failed to initialize script program!\n' + e.details());
	}
}